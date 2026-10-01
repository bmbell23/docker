#!/usr/bin/env bash
# GitOps reconciler (docker#45, agent-bus thread 016). Desired state = origin/main of each
# repo in dagu/deploy-repos.yaml; this closes the gap no matter who merged or how
# (bin/ship-pr or the GitHub UI). Run every 2 min by dagu/dags/deploy-reconciler.yaml.
#
# Per repo, in order:
#   1. version  a PR merged since the last "vX.Y.Z: ..." commit (merged outside ship-pr):
#               add the version.txt commit + tag on origin/main, the way ship-pr does.
#               Waits RECONCILE_GRACE s after the merge so it never races ship-pr, and
#               syncs/deploys nothing for that repo until the tip is versioned.
#               Built with plumbing, so it never touches a working tree.
#   2. sync     fast-forward the main clone. Dirty / off main / diverged: skip and alert.
#               Never stash, reset or discard.
#   3. tidy     remove worktrees of merged PRs: only clean ones whose tip is the merged head.
#   4. deploy   if the repo has an executable ./deploy: tag its images :previous, run it.
#   5. apk      if the repo has an executable ./build-apk (agent-bus thread 017's contract; until it
#               lands, the registry's `apk:` names the repo's existing script): once the clone is at origin/main and
#               deployed, rebuild the APK for that commit and say so (docker#51).
# Then, for all repos: announce   any compose container under a repo's path that is new or
#               recreated since the last run (a deploy, however it was done; docker#47).
#
# State for the Dashboard: logs/deploy/state.json (format in thread 016). Posts to #infra
# as Biscuit on changes only: a deploy, a version, a repo going red or green again.
# Red alerts and deploys @mention Brandon.
#
#   reconcile.sh [--dry-run] [--sweep] [--only <name>]
#     --dry-run  say what would happen; push, merge, deploy, remove and post nothing
#     --sweep    tidy worktrees even if main didn't move (normally only after a merge)
set -uo pipefail

DOCKER=/home/brandon/projects/docker
REG="${RECONCILE_REGISTRY:-$DOCKER/dagu/deploy-repos.yaml}"
OUT="${RECONCILE_OUT:-$DOCKER/logs/deploy}"
STATE="$OUT/state.json"
SAY="${RECONCILE_SAY:-/home/brandon/projects/agent-bus/bin/say}"
CHANNEL="${RECONCILE_CHANNEL:-#infra}"
GRACE="${RECONCILE_GRACE:-180}"
DEPLOY_TIMEOUT="${RECONCILE_DEPLOY_TIMEOUT:-900}"
APK_TIMEOUT="${RECONCILE_APK_TIMEOUT:-900}"
DASH="http://100.69.184.113:8014/dags/deploy-reconciler"

dry=0; sweep=0; only=""
while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run) dry=1 ;;
    --sweep) sweep=1 ;;
    --only) only="${2:?--only needs a repo name}"; shift ;;
    *) sed -n '2,22p' "$0"; exit 2 ;;
    esac
    shift
done

mkdir -p "$OUT"
exec 9>"$OUT/.lock"
flock -n 9 || { echo "another reconcile is running"; exit 0; }
[ -s "$STATE" ] || echo '{"repos":{}}' > "$STATE"
if ! jq -e '.repos | type == "object"' "$STATE" >/dev/null 2>&1; then   # never alert-loop on a bad file
    mv "$STATE" "$STATE.corrupt-$(date +%s)"; echo '{"repos":{}}' > "$STATE"
    echo "state.json was unreadable; moved aside and started fresh" >&2
fi

strikes() {   # strikes <kind> add|clear -> prints the count; transient failures alert on the 3rd
    local f="$OUT/.strikes-$name-$1" n
    if [ "$2" = clear ]; then rm -f "$f"; echo 0; return; fi
    n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); [ "$dry" = 1 ] || echo "$n" > "$f"; echo "$n"
}

log() { echo "[$name] $*"; }

post() {   # Biscuit, not an agent: costs nothing, wakes nobody
    if [ "$dry" = 1 ]; then echo "[dry-run] would post: $1"; return 0; fi
    printf '%s\n' "$1" | "$SAY" biscuit "$CHANNEL" - \
        || { echo "ALERT NOT DELIVERED: $1" >&2; logger -t reconcile "ALERT NOT DELIVERED: $1"; }
}

prev() { jq -r --arg n "$name" ".repos[\$n].$1 // empty" "$STATE"; }

record() {   # record <status> <message> [log] [rollback]; atomic for the Dashboard
    [ "$dry" = 1 ] && { log "[dry-run] state: $1: $2"; return 0; }
    jq --arg n "$name" --arg path "$path" --arg dep "${deployed:-}" --arg org "${origin:0:7}" \
       --arg st "$1" --arg msg "$2" --arg lg "${3:-}" --arg rb "${4:-}" --arg ts "$(date -Iseconds)" \
       --argjson auto "$auto" \
       '.updated=$ts | .repos[$n] = ((.repos[$n] // {}) + {path:$path, deployed_sha:$dep, origin_sha:$org,
         status:$st, ts:$ts, message:$msg, auto_deploy:$auto}
         + (if $lg != "" then {log:$lg} else {} end) + (if $rb != "" then {rollback_tag:$rb} else {} end))' \
       "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

# Alert once per (status, commit); say so again when it clears.
settle() {   # settle <status> <message> [log] [rollback]
    local was was_org; was=$(prev status); was_org=$(prev origin_sha)
    case "$1" in
    ok) case "$was" in failed|skipped-*) post "\`$name\` is back in step with main (${origin:0:7})." ;; esac ;;
    *)  [ "$was" = "$1" ] && [ "$was_org" = "${origin:0:7}" ] || post "@brandon \`$name\` $1: $2 $DASH" ;;
    esac
    record "$@"
}

version_failed() {   # sync/deploy wait for the version; alert if it keeps failing
    log "$1"
    [ "$(strikes version add)" -ge 3 ] && settle failed "versioning keeps failing: $1"
}

version_main() {   # step 1
    local subj cur latest lastv age ma mi pa ta tb tc v tree commit idx body
    [[ "$(git log -1 --format=%s origin/main)" =~ ^v[0-9]+\.[0-9]+\.[0-9]+: ]] && return 0
    git tag --points-at origin/main | grep -q '^v[0-9]' && return 0
    # Only PR merges get a version (squash "Title (#N)" or "Merge pull request #N"): direct
    # pushes like agent-bus's own "bus: ..." sync commits don't.
    lastv=$(git log -1 --format=%H -E --grep='^v[0-9]+\.[0-9]+\.[0-9]+:' origin/main)
    body=$(git log --format='%ct %s' "${lastv:+$lastv..}origin/main" | grep -E '^[0-9]+ (.*\(#[0-9]+\)$|Merge pull request #)' | head -20)
    [ -n "$body" ] || return 0
    age=$(( $(date +%s) - ${body%% *} ))                     # newest PR merge, not the tip: bus commits keep moving that
    body=$(cut -d' ' -f2- <<<"$body"); subj=$(head -1 <<<"$body"); body=$(sed 's/^/- /' <<<"$body")
    cur=$(git show origin/main:version.txt 2>/dev/null | tr -d '[:space:]')
    latest=$(git tag -l 'v*.*.*' --sort=-v:refname | head -1); latest="${latest#v}"
    [ -n "$cur$latest" ] || return 0                       # never versioned: nothing to continue
    # ship-pr versions within seconds of merging; wait for it, and deploy nothing unversioned meanwhile.
    [ "$age" -ge "$GRACE" ] || { log "unversioned merge is ${age}s old; giving ship-pr until ${GRACE}s"; return 1; }

    [ -n "$cur" ] || cur="$latest"
    IFS=. read -r ma mi pa <<<"$cur"
    if [ -n "$latest" ]; then IFS=. read -r ta tb tc <<<"$latest"; [ "$ta.$tb" = "$ma.$mi" ] && [ "$tc" -gt "$pa" ] && pa=$tc; fi
    v="$ma.$mi.$((pa + 1))"
    if [ "$dry" = 1 ]; then log "[dry-run] would version origin/main as v$v: $subj"; return 0; fi

    # An empty $commit would make the push below a branch delete: every step is checked.
    idx=$(mktemp)
    GIT_INDEX_FILE="$idx" git read-tree origin/main \
        && GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$(echo "$v" | git hash-object -w --stdin),version.txt" \
        && tree=$(GIT_INDEX_FILE="$idx" git write-tree) \
        && commit=$(git commit-tree "$tree" -p origin/main -m "v$v: $subj" \
                    -m "Merged outside ship-pr; versioned by the deploy reconciler (docker#45)." -m "$body")
    rm -f "$idx"
    [[ "${commit:-}" =~ ^[0-9a-f]{40}$ ]] || { version_failed "couldn't build the v$v commit"; return 1; }
    git tag -a "v$v" -m "Version $v" "$commit" || { version_failed "tag v$v already exists locally"; return 1; }
    if git push -q --atomic origin "$commit:refs/heads/main" "refs/tags/v$v" 2>"$OUT/.push-err"; then
        strikes version clear >/dev/null
        git fetch -q origin
        log "versioned v$v"
        post "Versioned \`$name\` **v$v**: $subj (merged outside ship-pr)."
    else
        git tag -d "v$v" >/dev/null                         # usually someone pushed first; next run retries
        version_failed "push of v$v rejected: $(head -2 "$OUT/.push-err")"
        return 1
    fi
}

tidy_worktrees() {   # step 3
    local wt br pr oid
    git worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} /^branch /{print p "\t" substr($0,19)}' |
    while IFS=$'\t' read -r wt br; do
        pr=; oid=
        [ "$wt" != "$path" ] && [[ "$wt" == "$HOME/worktrees/"* ]] || continue
        read -r pr oid < <(gh pr list --head "$br" --state merged --json number,headRefOid \
                             -q '.[0] | "\(.number) \(.headRefOid)"' 2>/dev/null) || true
        [ -n "${pr:-}" ] && [ "$pr" != null ] || continue
        [ "$(gh pr list --head "$br" --state open --json number -q length 2>/dev/null)" = 0 ] || continue
        if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then log "kept $wt: PR #$pr merged but it has uncommitted work"; continue; fi
        # remove would also delete ignored files: keep anything that isn't a rebuildable cache
        if git -C "$wt" status --porcelain --ignored 2>/dev/null | sed -n 's/^!! //p' \
             | grep -qvE '(^|/)(__pycache__|node_modules|\.pytest_cache|\.venv|venv|\.mypy_cache|\.ruff_cache)/?$|\.pyc$'; then
            log "kept $wt: PR #$pr merged but it has ignored files (.env, data?)"; continue
        fi
        if [ "$(git -C "$wt" rev-parse HEAD)" != "$oid" ]; then log "kept $wt: commits since PR #$pr merged"; continue; fi
        if [ "$dry" = 1 ]; then log "[dry-run] would remove $wt (PR #$pr merged)"; continue; fi
        git worktree remove "$wt" && git branch -D "$br" >/dev/null && log "removed $wt (PR #$pr merged)"
        git push -q origin --delete "$br" 2>/dev/null || true
    done
}

tag_previous() {   # rollback point: each running container's image, retagged :previous
    local c img base tags=""
    for c in $(docker compose ps -q 2>/dev/null); do
        img=$(docker inspect -f '{{.Config.Image}}' "$c") || continue
        base="$img"; [[ "${img##*/}" == *:* ]] && base="${img%:*}"
        [ "$dry" = 1 ] || docker tag "$(docker inspect -f '{{.Image}}' "$c")" "$base:previous" || continue
        tags="${tags:+$tags }$base:previous"
    done
    echo "$tags"
}

reconcile_one() {
    local branch head moved=0 rb lg rc v
    cd "$path" 2>/dev/null || { origin=""; deployed=""; settle failed "no repo at $path"; return; }
    deployed=$(prev deployed_sha)
    if ! err=$(git fetch -q --prune origin 2>&1); then   # alert on the 3rd miss in a row, not a blip
        log "git fetch failed: $err"
        [ "$(strikes fetch add)" -ge 3 ] && { origin=$(prev origin_sha); settle failed "git fetch failed 3 runs in a row: $err"; }
        return
    fi
    strikes fetch clear >/dev/null
    origin=$(git rev-parse origin/main)

    [ "$do_version" = false ] || version_main || return 0
    origin=$(git rev-parse origin/main)

    branch=$(git symbolic-ref --short -q HEAD || echo detached)
    head=$(git rev-parse HEAD)
    if [ "$head" != "$origin" ]; then
        [ "$branch" = main ] || { settle skipped-offmain "main clone is on \`$branch\`, not main; changed nothing."; return; }
        [ -z "$(git status --porcelain --untracked-files=no)" ] \
            || { settle skipped-dirty "main clone has uncommitted changes to tracked files; changed nothing until they're committed or dropped."; return; }
        git merge-base --is-ancestor HEAD origin/main \
            || { settle skipped-nonff "main clone has commits that aren't on origin/main; changed nothing."; return; }
        if [ "$dry" = 1 ]; then log "[dry-run] would fast-forward ${head:0:7} -> ${origin:0:7}"
        elif ! err=$(git merge -q --ff-only origin/main 2>&1); then
            settle skipped-nonff "fast-forward failed: $(echo "$err" | head -3)"; return
        fi
        moved=1
    fi
    head=$(git rev-parse HEAD); [ "$dry" = 1 ] && head="$origin"

    [ "$moved" = 1 ] || [ "$sweep" = 1 ] && tidy_worktrees

    if [ "$do_deploy" = false ] || [ ! -x deploy ]; then
        auto=false; deployed="${head:0:7}"; settle ok "in step with main; no ./deploy, so nothing to run."; return
    fi
    auto=true
    # First sight (new repo, lost state): this commit counts as deployed unless main just moved.
    [ -n "$deployed" ] || [ "$moved" = 1 ] || deployed="${head:0:7}"
    if [ "$deployed" = "${head:0:7}" ]; then settle ok "$(prev message || true)"; return; fi
    if [ "$(prev status)" = failed ] && [ "$(prev origin_sha)" = "${origin:0:7}" ]; then return; fi   # alerted already; next merge retries

    v=$(cat version.txt 2>/dev/null || echo "${head:0:7}")
    if [ "$dry" = 1 ]; then log "[dry-run] would tag :previous and run ./deploy for v$v"; return; fi
    lg="$OUT/$name-$(date +%Y%m%d-%H%M%S).log"
    case "$(prev status)" in
    failed|deploying) rb=$(prev rollback_tag) ;;            # containers may be half-deployed: keep the last good :previous
    *) rb=$(tag_previous) ;;
    esac
    record deploying "deploying v$v" "$lg" "$rb"
    timeout -k 30 "$DEPLOY_TIMEOUT" ./deploy </dev/null >"$lg" 2>&1 9>&-; rc=$?
    ls -t "$OUT/$name"-*.log 2>/dev/null | tail -n +21 | xargs -r rm -f --     # keep 20 logs per repo
    if [ "$rc" = 0 ]; then
        deployed="${head:0:7}"
        log "deployed v$v"
        # no post here: announce_deploys says it (with @brandon) once the containers are recreated
        record ok "deployed v$v" "$lg" "$rb"
    else
        settle failed "\`./deploy\` exited $rc for v$v. Rollback images: ${rb:-none}. Log: \`$lg\`
\`\`\`
$(tail -n 8 "$lg")
\`\`\`" "$lg" "$rb"
    fi
}

record_apk() {   # record_apk <status> <built sha> <message> [log]; apk_* fields only, beside the deploy's
    [ "$dry" = 1 ] && { log "[dry-run] apk state: $1: $3"; return 0; }
    jq --arg n "$name" --arg st "$1" --arg b "$2" --arg t "$sha" --arg msg "$3" --arg lg "${4:-}" --arg ts "$(date -Iseconds)" \
       '.updated=$ts | .repos[$n] = ((.repos[$n] // {}) + {apk_status:$st, apk_sha:$b, apk_tried:$t, apk_message:$msg, apk_ts:$ts}
         + (if $lg != "" then {apk_log:$lg} else {} end))' \
       "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

build_apk() {   # step 5 (docker#51, thread 017): the APK follows main the way the containers do
    local built lg rc v line
    [ "$do_apk" != false ] && cd "$path" 2>/dev/null || return 0
    [ -x build-apk ] && apk=build-apk                          # the file IS the opt-in; registry `apk:` is the bridge
    [ -n "$apk" ] || return 0
    [ "$(prev status)" = ok ] || return 0                     # skipped, deploying or failed: not in step yet
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || return 0
    sha=$(git rev-parse --short=7 HEAD); built=$(prev apk_sha)
    # First sight: this commit counts as built, so turning it on doesn't start every gradle build at once.
    [ -n "$built" ] || { record_apk ok "$sha" "first sight; counted as built"; return 0; }
    [ "$built" = "$sha" ] && return 0
    [ "$(prev apk_status)" = failed ] && [ "$(prev apk_tried)" = "$sha" ] && return 0   # alerted already; next merge retries
    case "$(date +%H)" in 01|02|03) log "apk waits: 01:00-04:00 is the backup window"; return 0 ;; esac
    [ -x "$apk" ] || { [ "$(prev apk_tried)" = "$sha" ] || post "@brandon ❌ \`$name\` APK build failed: \`$apk\` isn't an executable file in the repo. $DASH"
                       record_apk failed "$built" "no executable $apk"; return 0; }
    v=$(tr -d '[:space:]' < version.txt 2>/dev/null)
    if [ "$dry" = 1 ]; then log "[dry-run] would run ./$apk for ${v:+v$v }($sha)"; return 0; fi
    lg="$OUT/$name-apk-$(date +%Y%m%d-%H%M%S).log"
    record_apk building "$built" "building ${v:+v$v }($sha)" "$lg"
    # Builds run one at a time: the repo loop is serial and the whole run holds the lock.
    # No gradle daemon: it would outlive this ssh session and could hold the lock (fd 9).
    # MealForge's simple-app has no local.properties, so the SDK comes from ANDROID_HOME.
    ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}" GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false" \
        timeout -k 30 "$APK_TIMEOUT" "./$apk" </dev/null >"$lg" 2>&1 9>&-; rc=$?
    ls -t "$OUT/$name"-*.log 2>/dev/null | tail -n +21 | xargs -r rm -f --
    case "$rc" in
    0)  # thread 017: the last line is "<versionName> <link>"; older scripts don't print one
        line=$(grep -v '^[[:space:]]*$' "$lg" | tail -1)
        [[ "$line" =~ ^[^[:space:]]+\ [^[:space:]]+$ ]] || line="${v:+v$v}"
        log "apk rebuilt for $sha"
        record_apk ok "$sha" "rebuilt ${line:-$sha}" "$lg"
        post "@brandon 📱 **$name** APK rebuilt: ${line:-$sha} ($sha)" ;;
    75) log "apk: nothing to rebuild for $sha"; record_apk ok "$sha" "nothing to rebuild ($sha)" "$lg"; return 0 ;;
    *)  post "@brandon ❌ \`$name\` APK build failed: \`./$apk\` exited $rc for ${v:+v$v }($sha). The old APK is still served. Log: \`$lg\`
\`\`\`
$(tail -n 8 "$lg")
\`\`\`"
        record_apk failed "$built" "./$apk exited $rc" "$lg"; return 0 ;;
    esac
    # The next merge would stop at skipped-dirty anyway; say why now.
    [ -z "$(git status --porcelain --untracked-files=no)" ] \
        || post "@brandon \`$name\`: \`./$apk\` changed tracked files in the main clone, so the next merge will skip it until that's fixed: $(git status --porcelain --untracked-files=no | head -5 | awk '{print $2}' | paste -sd' ')"
}

announce_deploys() {   # docker#47: most deploys are a hand/agent `docker compose up`, not ./deploy
    local seen="$OUT/containers.json" cur first=0 repo rpath v sha names
    [ -s "$seen" ] && jq -e 'type == "object"' "$seen" >/dev/null 2>&1 || first=1
    # name \t compose working_dir \t Created (changes only on create/recreate, not a crash restart)
    cur=$(docker ps -q | xargs -r docker inspect -f \
            '{{.Name}}{{"\t"}}{{index .Config.Labels "com.docker.compose.project.working_dir"}}{{"\t"}}{{.Created}}' \
          | sed 's|^/||' | awk -F'\t' '$2 != ""') || return 0
    [ -n "$cur" ] || return 0
    if [ "$first" = 0 ]; then
        while IFS=$'\t' read -r -u 4 repo rpath _; do
            [ -z "$only" ] || [ "$only" = "$repo" ] || continue
            names=$(awk -F'\t' -v p="$rpath" '$2 == p || index($2, p "/") == 1 {print $1 "\t" $3}' <<<"$cur" |
                    while IFS=$'\t' read -r c t; do
                        [ "$(jq -r --arg c "$c" '.[$c] // empty' "$seen")" = "$t" ] || echo "$c"
                    done | sort | paste -sd, - | sed 's/,/, /g')
            [ -n "$names" ] || continue
            v=$(cat "$rpath/version.txt" 2>/dev/null | tr -d '[:space:]')
            sha=$(git -C "$rpath" rev-parse --short=7 HEAD 2>/dev/null)
            post "@brandon Deployed \`$repo\`${v:+ **v$v**}${sha:+ ($sha)}: $names"
        done 4<<<"$rows"
    fi
    [ "$dry" = 1 ] && return 0
    awk -F'\t' '{print $1 "\t" $3}' <<<"$cur" |
        jq -R 'split("\t") | {(.[0]): .[1]}' | jq -s --slurpfile old <(cat "$seen" 2>/dev/null || echo '{}') \
            '($old[0] // {}) + add' > "$seen.tmp" && mv "$seen.tmp" "$seen"
}

rows=$(python3 -c '
import sys, yaml
for r in yaml.safe_load(open(sys.argv[1]))["repos"]:
    print("\t".join([r["name"], r["path"]] + [str(r.get(k, True)).lower() for k in ("enabled", "deploy", "version", "build_apk")] + [r.get("apk", "")]))
' "$REG") && [ -n "$rows" ] || { echo "registry $REG unreadable or empty" >&2; exit 1; }

while IFS=$'\t' read -r -u 3 name path enabled do_deploy do_version do_apk apk; do
    [ -z "$only" ] || [ "$only" = "$name" ] || continue
    [ "$enabled" = false ] && continue
    auto=false
    ( reconcile_one; build_apk ) || echo "[$name] reconcile crashed (exit $?)"
done 3<<<"$rows"
announce_deploys
