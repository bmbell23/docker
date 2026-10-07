#!/usr/bin/env python3
"""Rusty, the medic (docker#143, agent-bus docs/SELF-HEAL.md Tier 0).

Alertmanager sends alerts that carry a `remedy:` label here instead of to Mongo. For each one the
medic runs that one playbook against the target listed in targets.yaml: 2 tries, 5 min apart, and a
breaker of 3 attempts per target per 24 h. Every attempt and result goes to #infra as @rusty.
Recovered: nobody is paged. Gave up, no target, or breaker open: the original payload goes to
Mongo's /alert with a `medic` annotation saying what was tried, and Mongo pages the owner as before.

Playbooks, and nothing else: recreate (PID-kill + `docker compose up -d <svc>`), user-unit
(`systemctl --user restart`), dnat (the root-owned medic-dnat wrapper via sudo). No down/rm/prune.

Stdlib + PyYAML only. Run by systemd/medic.service; every knob is an env var (see CONFIG below).
"""
import copy
import json
import queue
import os
import re
import signal
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
DOCKER_REPO = os.path.dirname(os.path.dirname(HERE))

# CONFIG
LISTEN = os.environ.get("MEDIC_LISTEN", "127.0.0.1:9097")
TARGETS = os.environ.get("MEDIC_TARGETS", os.path.join(HERE, "targets.yaml"))
REPOS = os.environ.get("MEDIC_REPOS", os.path.join(DOCKER_REPO, "dagu", "deploy-repos.yaml"))
STATE = os.environ.get("MEDIC_STATE", os.path.expanduser("~/.local/state/medic/state.json"))
AM_URL = os.environ.get("MEDIC_AM_URL", "http://127.0.0.1:9093")
MONGO_URL = os.environ.get("MEDIC_MONGO_URL", "")   # empty: agentbus_mongo's IP, looked up per forward
SAY = os.environ.get("MEDIC_SAY", "/home/brandon/projects/agent-bus/bin/say rusty infra -").split()
DOCKER = os.environ.get("MEDIC_DOCKER", "docker")
SYSTEMCTL = os.environ.get("MEDIC_SYSTEMCTL", "systemctl")
DNAT = os.environ.get("MEDIC_DNAT", "sudo -n /usr/local/sbin/medic-dnat").split()
TRIES = 2
RETRY_WAIT = float(os.environ.get("MEDIC_RETRY_WAIT", "300"))
SETTLE = float(os.environ.get("MEDIC_SETTLE", "5"))   # after `up -d`, before checking it's running
BREAKER = 3
WINDOW = 24 * 3600

# Never touched, whatever targets.yaml says: the office, databases, and the stack that alerts us.
DENY = re.compile(r"mattermost|postgres|mariadb|mysql|redis|(^|[-_])db$|prometheus|alertmanager|grafana"
                  r"|cadvisor|node[-_]?exporter|blackbox|monitoring|agentbus|medic", re.I)

lock = threading.Lock()
jobs = {}   # fingerprint -> threading.Event, set when the alert resolves


def log(msg):
    print(msg, flush=True)


# ---- state: attempts per target (the breaker) and fingerprints already handed to Mongo ----

def load_state():
    try:
        with open(STATE) as f:
            s = json.load(f)
    except (OSError, ValueError):
        s = {}
    s.setdefault("attempts", {})
    s.setdefault("gave_up", {})
    s.setdefault("inflight", {})
    return s


def save_state(s):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f, indent=1)
    os.replace(tmp, STATE)


def recent_attempts(s, key, now):
    s["attempts"][key] = [t for t in s["attempts"].get(key, []) if now - t < WINDOW]
    return len(s["attempts"][key])


def take_attempt(key):
    """Record one attempt for key, unless the breaker is open. True if it may go ahead."""
    with lock:
        s = load_state()
        now = time.time()
        if recent_attempts(s, key, now) >= BREAKER:
            save_state(s)
            return False
        s["attempts"][key].append(now)
        save_state(s)
        return True


def mark_gave_up(fp, on):
    with lock:
        s = load_state()
        if on:
            s["gave_up"][fp] = time.time()
        else:
            s["gave_up"].pop(fp, None)
        # A page Alertmanager never resolved (silenced, deleted) shouldn't stay forever.
        s["gave_up"] = {k: t for k, t in s["gave_up"].items() if time.time() - t < 7 * 24 * 3600}
        save_state(s)


def gave_up(fp):
    with lock:
        return fp in load_state()["gave_up"]


def mark_inflight(fp, page):
    """Persist what's being worked on, so a restart mid-fix pages instead of forgetting it."""
    with lock:
        s = load_state()
        if page:
            s["inflight"][fp] = page
        else:
            s["inflight"].pop(fp, None)
        save_state(s)


def recover_inflight():
    """At startup: anything a previous run was still fixing goes to Mongo now."""
    with lock:
        s = load_state()
        left, s["inflight"] = s["inflight"], {}
        save_state(s)
    for fp, page in left.items():
        forward_and_stop(page["payload"], page["alert"], "the medic restarted in the middle of fixing this; not retried")


# ---- talking: #infra as rusty, and Mongo ----

said = queue.Queue()


def say(text):
    """Queue a line for #infra. Posting happens on its own thread, in order: if Mattermost is
    down (likely, mid-incident), fixes and pages don't wait on it."""
    log(f"say: {text}")
    said.put(text)


def sayer():
    while True:
        text = said.get()
        try:
            subprocess.run(SAY, input=text, text=True, timeout=60, check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired) as e:
            log(f"say failed: {e}")
        said.task_done()


threading.Thread(target=sayer, daemon=True).start()


def mongo_url():
    if MONGO_URL:
        return MONGO_URL
    out = run([DOCKER, "inspect", "agentbus_mongo", "-f",
               '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}\n{{end}}'])[1]
    ips = dict(line.split() for line in out.splitlines() if len(line.split()) == 2)
    ip = ips.get("monitoring_default") or next(iter(ips.values()), "")
    return f"http://{ip}:9095/alert" if ip else ""


def forward(payload, alert, note):
    """Hand one alert to Mongo: the original payload, just this alert, plus `medic: <note>`."""
    page = copy.deepcopy(payload)
    a = copy.deepcopy(alert)
    if note:
        a.setdefault("annotations", {})["medic"] = note
    page["alerts"] = [a]
    page["status"] = a.get("status", page.get("status"))
    url = mongo_url()
    log(f"forward {a.get('fingerprint')} to {url or '(no Mongo)'}: {note}")
    if not url:
        return False
    for i in range(3):
        try:
            req = urllib.request.Request(url, json.dumps(page).encode(), {"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=15).read()
            return True
        except OSError as e:
            log(f"forward failed ({i + 1}/3): {e}")
            time.sleep(5)
    say(f"Couldn't reach Mongo to page about {name_of(alert)}. Somebody look at this by hand: {note}")
    return False


def still_firing(fp):
    """Ask Alertmanager. If it doesn't answer, assume it's still down (keeps trying, then pages)."""
    try:
        with urllib.request.urlopen(f"{AM_URL}/api/v2/alerts?active=true&silenced=false&inhibited=false",
                                    timeout=10) as r:
            return any(a.get("fingerprint") == fp for a in json.load(r))
    except (OSError, ValueError) as e:
        log(f"alertmanager: {e}")
        return True


# ---- playbooks ----

def run(cmd, cwd=None, timeout=300):
    try:
        p = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout, check=False)
        return p.returncode, (p.stdout + p.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f) or {}


def resolve(playbook, key):
    """The allowlisted target for this playbook and key, or (None, why not)."""
    if playbook not in ("recreate", "user-unit", "dnat"):
        return None, f"`{playbook}` isn't one of my playbooks"
    t = (load_yaml(TARGETS).get(playbook) or {}).get(key)
    if not t:
        return None, f"no {playbook} target for `{key}` in my list"
    if playbook == "recreate":
        repos = {r["name"]: r["path"] for r in load_yaml(REPOS).get("repos", [])}
        repo = repos.get(t.get("repo"))
        if not repo:
            return None, f"repo `{t.get('repo')}` isn't in deploy-repos.yaml"
        d = os.path.realpath(os.path.join(repo, t.get("dir", ".")))
        if not (d + "/").startswith(os.path.realpath(repo) + "/") and d != os.path.realpath(repo):
            return None, f"`{t.get('dir')}` is outside {repo}"
        if not any(os.path.exists(os.path.join(d, c)) for c in ("docker-compose.yml", "compose.yaml", "compose.yml")):
            return None, f"no compose file in {d}"
        svc = str(t.get("service", ""))
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", svc) or DENY.search(svc) or DENY.search(d):
            return None, f"`{svc}` in {d} is on my never-touch list"
        return {"dir": d, "service": svc}, ""
    if playbook == "user-unit":
        unit = str(t.get("unit", ""))
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9@_.:-]*\.(service|timer)", unit) or DENY.search(unit):
            return None, f"unit `{unit}` isn't allowed"
        return {"unit": unit}, ""
    port = str(t.get("port", ""))
    if not re.fullmatch(r"[0-9]{1,5}", port):
        return None, f"bad port `{port}`"
    return {"port": port}, ""


def recreate(t):
    d, svc = t["dir"], t["service"]
    cid = run([DOCKER, "compose", "ps", "-q", svc], cwd=d)[1].splitlines()
    force = []
    if cid:
        pid = run([DOCKER, "inspect", cid[0], "-f", "{{.State.Pid}}"])[1]
        if pid.isdigit() and int(pid) > 1:
            try:
                os.kill(int(pid), signal.SIGTERM)   # `docker restart`/stop are denied here (CLAUDE.md)
                for _ in range(30):
                    if run([DOCKER, "inspect", cid[0], "-f", "{{.State.Running}}"])[1] != "true":
                        break
                    time.sleep(1)
                else:   # PID 1 ignored SIGTERM: a plain `up -d` would be a no-op
                    force = ["--force-recreate"]
            except OSError as e:
                log(f"kill {pid}: {e}; falling back to --force-recreate")
                force = ["--force-recreate"]
    rc, out = run([DOCKER, "compose", "up", "-d", "--no-deps", *force, svc], cwd=d)   # never its db
    if rc:
        return False, f"`docker compose up -d {svc}` failed: {out[-300:]}"
    time.sleep(SETTLE)
    cid = run([DOCKER, "compose", "ps", "-q", svc], cwd=d)[1].splitlines()
    running = cid and run([DOCKER, "inspect", cid[0], "-f", "{{.State.Running}}"])[1] == "true"
    return bool(running), "container is up again" if running else "container isn't running after `up -d`"


def user_unit(t):
    rc, out = run([SYSTEMCTL, "--user", "restart", t["unit"]], timeout=120)
    if rc:
        return False, f"restart failed: {out[-300:]}"
    state = run([SYSTEMCTL, "--user", "is-active", t["unit"]])[1]
    return state == "active", f"unit is {state}"


def dnat(t):
    rc, out = run([*DNAT, t["port"]], timeout=60)
    return rc == 0, out[-300:] or "no stale rules"


PLAYBOOKS = {"recreate": recreate, "user-unit": user_unit, "dnat": dnat}


# ---- one alert, start to finish ----

def name_of(alert):
    lb = alert.get("labels", {})
    return lb.get("name") or lb.get("remedy_key") or lb.get("key") or lb.get("alertname", "?")


def treat(payload, alert, resolved):
    fp = alert["fingerprint"]
    lb = alert.get("labels", {})
    playbook = lb.get("remedy", "")
    key = lb.get("remedy_key") or lb.get("key") or ""
    who = name_of(alert)
    try:
        t, why = resolve(playbook, key)
        if not t:
            forward_and_stop(payload, alert, f"{why}; I didn't touch anything")
            return
        bkey = f"{playbook}:{key}"
        tries = 0
        for n in range(1, TRIES + 1):
            if not take_attempt(bkey):
                say(f"🦖 {who} ({lb.get('alertname')}) is down again, but I've tried `{playbook} {key}` "
                    f"{BREAKER} times in 24 h. Breaker's open; paging the owner through Mongo.")
                forward_and_stop(payload, alert, f"breaker open: {playbook} {key} ×{BREAKER} in 24 h, not tried again")
                return
            tries = n
            say(f"🦖 {who} is down ({lb.get('alertname')}). Trying `{playbook} {key}`, try {n}/{TRIES}.")
            ok, detail = PLAYBOOKS[playbook](t)
            say(f"`{playbook} {key}` {'done' if ok else 'failed'}: {detail}. "
                f"Checking again in {int(RETRY_WAIT // 60)} min.")
            if resolved.wait(RETRY_WAIT) or not still_firing(fp):
                say(f"🦖 {who} is back after `{playbook} {key}` (try {n}/{TRIES}). Nobody paged.")
                return
        say(f"🦖 {who} is still down after `{playbook} {key}` ×{tries}. Paging the owner through Mongo.")
        forward_and_stop(payload, alert, f"{playbook} {key} ×{tries}, still down")
    except Exception as e:   # never swallow a page because of a bug in here
        log(f"treat {fp}: {e!r}")
        forward_and_stop(payload, alert, f"the medic crashed on it ({type(e).__name__}); didn't finish")
    finally:
        with lock:
            if jobs.get(fp) is resolved:   # not a newer job for the same alert
                jobs.pop(fp)
        try:
            mark_inflight(fp, None)
        except Exception as e:
            log(f"state: {e!r}")


def forward_and_stop(payload, alert, note):
    """Page first, bookkeeping second: a full disk must not eat the page."""
    try:
        forward(payload, alert, note)
    except Exception as e:
        log(f"forward {alert.get('fingerprint')}: {e!r}")
    try:
        mark_gave_up(alert["fingerprint"], True)
    except Exception as e:
        log(f"state: {e!r}")


def handle(payload):
    for alert in payload.get("alerts", []):
        try:
            handle_one(payload, alert)
        except Exception as e:         # a bug here must still page
            log(f"handle {alert.get('fingerprint')}: {e!r}")
            forward(payload, alert, f"the medic choked on this alert ({type(e).__name__}); didn't touch anything")


def handle_one(payload, alert):
    fp = alert.get("fingerprint")
    if not fp:
        forward(payload, alert, "no fingerprint; didn't touch anything")
        return
    if alert.get("status") == "resolved":
        with lock:
            ev = jobs.pop(fp, None)    # popped now: a re-fire right after starts afresh
        if ev:
            ev.set()
        elif gave_up(fp):              # Mongo paged about it, so Mongo hears it's over
            mark_gave_up(fp, False)
            forward(payload, alert, "")
        return
    with lock:
        if fp in jobs:                 # already on it; Alertmanager re-sent the group
            return
        ev = jobs[fp] = threading.Event()
    if gave_up(fp):                    # already paged: repeats go to Mongo as they always did
        with lock:
            jobs.pop(fp, None)
        forward(payload, alert, "")
        return
    try:
        mark_inflight(fp, {"payload": payload, "alert": alert})
    except Exception as e:
        log(f"state: {e!r}")
    threading.Thread(target=treat, args=(payload, alert, ev), daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/alert":
            self.send_error(404)
            return
        try:
            payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        except ValueError:
            self.send_error(400)
            return
        handle(payload)
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        if self.path == "/healthz":
            body = b"ok\n"
        elif self.path == "/metrics":
            with lock:
                n = len(jobs)
            body = f"# TYPE medic_jobs gauge\nmedic_jobs {n}\n".encode()
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def main():
    host, port = LISTEN.rsplit(":", 1)
    srv = ThreadingHTTPServer((host, int(port)), Handler)
    log(f"medic listening on {LISTEN}")
    threading.Thread(target=recover_inflight, daemon=True).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
