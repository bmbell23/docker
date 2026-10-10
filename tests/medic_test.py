#!/usr/bin/env python3
"""scripts/medic/medic.py against a fake docker, a fake `say`, and fake Alertmanager/Mongo (docker#143).
Run: python3 tests/medic_test.py   (no Docker, Mattermost or network needed)"""
import importlib.util
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = tempfile.mkdtemp()
REPO = os.path.join(T, "repo")
for d in ("romm", "jellyfin"):
    os.makedirs(os.path.join(REPO, d))
    open(os.path.join(REPO, d, "docker-compose.yml"), "w").close()

DAGU = os.path.join(T, "dagu")   # docker#159: dags/, data/{proc,suspend}/, .drain.env
for d in ("dags", "data/proc/pve01-documents-restic", "data/suspend"):
    os.makedirs(os.path.join(DAGU, d))
open(os.path.join(DAGU, "dags", "pve01-documents-restic.yaml"), "w").close()
with open(os.path.join(DAGU, ".drain.env"), "w") as f:
    f.write("DAGU_API_TOKEN='tok'\n")
PROC = os.path.join(DAGU, "data/proc/pve01-documents-restic/run.proc")
SUSPEND = os.path.join(DAGU, "data/suspend/pve01-documents-restic.suspend")

FAKE_DOCKER = os.path.join(T, "docker")
with open(FAKE_DOCKER, "w") as f:
    f.write(f"""#!/bin/sh
echo "$*" >> {T}/docker.log
case "$*" in
  "compose ps -q"*) echo cid1 ;;
  *State.Pid*) echo 0 ;;
  *State.Running*) echo true ;;
  "compose up"*) [ -e {T}/up-fails ] && {{ echo boom; exit 1; }} ;;
esac
exit 0
""")
FAKE_SAY = os.path.join(T, "say")
with open(FAKE_SAY, "w") as f:
    f.write(f"#!/bin/sh\ncat >> {T}/say.log; echo >> {T}/say.log\n")
os.chmod(FAKE_DOCKER, 0o755)
os.chmod(FAKE_SAY, 0o755)

with open(os.path.join(T, "repos.yaml"), "w") as f:
    f.write(f"repos:\n  - {{name: docker, path: {REPO}, enabled: true}}\n")
with open(os.path.join(T, "targets.yaml"), "w") as f:
    f.write("recreate:\n  romm: {repo: docker, dir: romm, service: romm}\n"
            "  romm-db: {repo: docker, dir: romm, service: romm-db}\n"
            "  escape: {repo: docker, dir: ../.., service: x}\n"
            "dagu-run:\n  documents: {dag: pve01-documents-restic}\n  ghost: {dag: no-such-dag}\n")


class Fake(BaseHTTPRequestHandler):
    firing = set()      # fingerprints Alertmanager says are active
    pages = []          # what reached Mongo
    starts = []         # (path, Authorization) of every Dagu start

    def do_GET(self):
        body = json.dumps([{"fingerprint": fp} for fp in Fake.firing]).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.startswith("/api/v1/dags/"):   # Dagu: the run shows up as a .proc for 0.3 s
            self.rfile.read(int(self.headers["Content-Length"]))
            Fake.starts.append((self.path, self.headers.get("Authorization")))
            open(PROC, "w").close()
            threading.Timer(0.3, os.remove, [PROC]).start()
            self.send_response(200)
            self.end_headers()
            return
        Fake.pages.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        self.send_response(200)
        self.end_headers()

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=srv.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{srv.server_port}"

os.environ.update(MEDIC_TARGETS=os.path.join(T, "targets.yaml"), MEDIC_REPOS=os.path.join(T, "repos.yaml"),
                  MEDIC_STATE=os.path.join(T, "state.json"), MEDIC_AM_URL=url, MEDIC_MONGO_URL=url + "/alert",
                  MEDIC_SAY=FAKE_SAY, MEDIC_DOCKER=FAKE_DOCKER, MEDIC_RETRY_WAIT="0.2", MEDIC_SETTLE="0",
                  MEDIC_DAGU_URL=url + "/api/v1", MEDIC_DAGU_HOME=DAGU, MEDIC_DAGU_GRACE="0.2")
spec = importlib.util.spec_from_file_location("medic", os.path.join(HERE, "scripts/medic/medic.py"))
medic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(medic)


def backup(fp="b1", repo="documents", status="firing"):
    return {"status": status, "fingerprint": fp,
            "labels": {"alertname": "BackupStale", "instance": "pve01", "repo": repo, "remedy": "dagu-run",
                       "remedy_key": repo, "owner": "peter", "severity": "critical"},
            "annotations": {"summary": f"pve01 restic {repo}: no good backup for 1d 7h"}}


def alert(fp="fp1", key="romm", status="firing", remedy="recreate"):
    return {"status": status, "fingerprint": fp,
            "labels": {"alertname": "ServiceDown", "key": key, "name": key.title(), "remedy": remedy,
                       "owner": "dakota", "severity": "critical"},
            "annotations": {"summary": f"{key} is down"}}


def send(*alerts):
    medic.handle({"version": "4", "status": alerts[0]["status"], "receiver": "medic", "alerts": list(alerts)})


def settle(timeout=5):
    end = time.time() + timeout
    while medic.jobs and time.time() < end:
        time.sleep(0.05)
    assert not medic.jobs, "medic still busy"
    time.sleep(0.1)                 # the last thread's finally
    medic.said.join()


def read(name):
    try:
        with open(os.path.join(T, name)) as f:
            return f.read()
    except OSError:
        return ""


class MedicTest(unittest.TestCase):
    def setUp(self):
        for n in ("docker.log", "say.log", "state.json", "up-fails", PROC, SUSPEND):
            try:
                os.remove(os.path.join(T, n))
            except OSError:
                pass
        Fake.firing, Fake.pages, Fake.starts = set(), [], []

    def test_recovers_on_first_try_and_pages_nobody(self):
        send(alert())
        settle()
        self.assertIn("compose up -d --no-deps romm", read("docker.log"))
        self.assertIn("Romm is back after `recreate romm` (try 1/2). Nobody paged.", read("say.log"))
        self.assertEqual(Fake.pages, [])

    def test_still_down_after_two_tries_pages_with_medic_note(self):
        Fake.firing = {"fp1"}
        send(alert())
        settle()
        self.assertEqual(read("docker.log").count("compose up -d --no-deps romm"), 2)
        self.assertEqual(len(Fake.pages), 1)
        a = Fake.pages[0]["alerts"][0]
        self.assertEqual(a["annotations"]["medic"], "recreate romm ×2, still down")
        self.assertEqual(a["annotations"]["summary"], "romm is down")   # the original payload, untouched
        self.assertEqual(Fake.pages[0]["receiver"], "medic")
        # Alertmanager's hourly repeat goes straight to Mongo, no new attempt, no note.
        send(alert())
        settle()
        self.assertEqual(read("docker.log").count("compose up -d --no-deps romm"), 2)
        self.assertNotIn("medic", Fake.pages[1]["alerts"][0]["annotations"])
        # And Mongo hears when it's over.
        send(alert(status="resolved"))
        self.assertEqual(Fake.pages[2]["status"], "resolved")
        self.assertFalse(medic.gave_up("fp1"))

    def test_breaker_opens_at_three_attempts_in_24h(self):
        Fake.firing = {"fp1", "fp2"}
        send(alert("fp1"))
        settle()                                   # 2 attempts
        send(alert("fp2"))
        settle()                                   # 1 more, then the breaker
        self.assertEqual(read("docker.log").count("compose up -d --no-deps romm"), 3)
        self.assertEqual(Fake.pages[-1]["alerts"][0]["annotations"]["medic"],
                         "breaker open: recreate romm ×3 in 24 h, not tried again")

    def test_failed_playbook_still_counts_and_pages(self):
        Fake.firing = {"fp1"}
        open(os.path.join(T, "up-fails"), "w").close()
        send(alert())
        settle()
        self.assertIn("`recreate romm` failed", read("say.log"))
        self.assertEqual(Fake.pages[0]["alerts"][0]["annotations"]["medic"], "recreate romm ×2, still down")

    def test_resolved_webhook_ends_the_wait(self):
        Fake.firing = {"fp1"}
        medic.RETRY_WAIT = 30
        try:
            send(alert())
            time.sleep(0.3)
            send(alert(status="resolved"))
            settle()
        finally:
            medic.RETRY_WAIT = 0.2
        self.assertEqual(read("docker.log").count("compose up -d --no-deps romm"), 1)
        self.assertEqual(Fake.pages, [])

    def test_untouchables_are_forwarded_without_running_anything(self):
        for fp, key, remedy, why in [("a", "artforge", "recreate", "no recreate target for `artforge`"),
                                     ("b", "romm-db", "recreate", "never-touch list"),
                                     ("c", "escape", "recreate", "outside"),
                                     ("d", "romm", "reboot", "`reboot` isn't one of my playbooks")]:
            send(alert(fp, key, remedy=remedy))
            settle()
            self.assertIn(why, Fake.pages[-1]["alerts"][0]["annotations"]["medic"])
        self.assertEqual(read("docker.log"), "")

    def test_restart_mid_fix_pages_on_startup(self):
        page = {"payload": {"version": "4", "receiver": "medic", "alerts": []}, "alert": alert()}
        with open(os.path.join(T, "state.json"), "w") as f:
            json.dump({"inflight": {"fp1": page}}, f)
        medic.recover_inflight()
        self.assertEqual(Fake.pages[0]["alerts"][0]["annotations"]["medic"],
                         "the medic restarted in the middle of fixing this; not retried")
        self.assertEqual(medic.load_state()["inflight"], {})

    def test_unwritable_state_still_pages(self):
        Fake.firing = {"fp1"}
        real = medic.save_state
        medic.save_state = lambda s: (_ for _ in ()).throw(OSError("disk full"))
        try:
            send(alert())
            settle()
        finally:
            medic.save_state = real
        self.assertEqual(len(Fake.pages), 1)
        self.assertIn("crashed", Fake.pages[0]["alerts"][0]["annotations"]["medic"])

    def test_refire_right_after_resolve_starts_a_new_job(self):
        Fake.firing = {"fp1"}
        medic.RETRY_WAIT = 30
        try:
            send(alert())
            time.sleep(0.3)
            send(alert(status="resolved"))
            send(alert())                 # flapped straight back
            time.sleep(0.3)
            self.assertIn("fp1", medic.jobs)
            send(alert(status="resolved"))
            settle()
        finally:
            medic.RETRY_WAIT = 0.2
        self.assertEqual(read("docker.log").count("compose up -d --no-deps romm"), 2)

    def test_one_job_per_alert_while_busy(self):
        Fake.firing = {"fp1"}
        send(alert())
        send(alert())
        settle()
        self.assertEqual(read("docker.log").count("compose up -d --no-deps romm"), 2)
        self.assertEqual(len(Fake.pages), 1)

    # docker#159: BackupStale -> one Dagu run, never two, never during maintenance.
    def test_stale_backup_runs_once_and_pages_nobody_when_it_lands(self):
        send(backup())
        settle()
        self.assertEqual(Fake.starts, [("/api/v1/dags/pve01-documents-restic/start", "Bearer tok")])
        self.assertIn("The documents backup is back after `dagu-run documents` (try 1/1). Nobody paged.",
                      read("say.log"))
        self.assertEqual(Fake.pages, [])

    def test_still_stale_after_the_run_pages_without_a_second_run(self):
        Fake.firing = {"b1"}
        send(backup())
        settle()
        self.assertEqual(len(Fake.starts), 1)
        self.assertIn("`pve01-documents-restic` ran", read("say.log"))
        self.assertEqual(Fake.pages[0]["alerts"][0]["annotations"]["medic"], "dagu-run documents ×1, still stale")

    def test_suspended_or_running_dag_is_not_started(self):
        for fp, path, why in [("b1", SUSPEND, "is suspended (a maintenance window still open?)"),
                              ("b2", PROC, "is already running")]:
            open(path, "w").close()
            send(backup(fp))
            settle()
            os.remove(path)
            self.assertIn(why, Fake.pages[-1]["alerts"][0]["annotations"]["medic"])
        self.assertEqual(Fake.starts, [])
        self.assertEqual(medic.load_state()["attempts"], {})   # a refusal isn't an attempt

    def test_unknown_dag_is_forwarded(self):
        send(backup(repo="ghost"))
        send(backup("b2", repo="pictures"))
        settle()
        self.assertIn("no DAG `no-such-dag`", Fake.pages[0]["alerts"][0]["annotations"]["medic"])
        self.assertIn("no dagu-run target for `pictures`", Fake.pages[1]["alerts"][0]["annotations"]["medic"])
        self.assertEqual(Fake.starts, [])


if __name__ == "__main__":
    sys.exit(unittest.main())
