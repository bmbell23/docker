#!/bin/bash
# Backup DAGs and docs/backup-inventory.yaml must agree (docker#78), both ways:
#   - every DAG tagged `backup` is named as a dag somewhere in the inventory
#     (a copy, a restore_test or a drive), so the Dashboard's Backup Overview shows it;
#   - every dag the inventory names has a file in dagu/dags/.
# Exit 0 = in sync, 1 = drift (listed). Run it before a PR that adds a backup DAG.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

python3 - "$ROOT" <<'PY'
import glob, os, sys, yaml

root = sys.argv[1]
dags = {}
for path in glob.glob(os.path.join(root, 'dagu/dags/*.yaml')):
    with open(path) as f:
        d = yaml.safe_load(f) or {}
    name = d.get('name') or os.path.splitext(os.path.basename(path))[0]
    dags[name] = set(d.get('tags') or [])

with open(os.path.join(root, 'docs/backup-inventory.yaml')) as f:
    inv = yaml.safe_load(f) or {}

named = set()
for e in (inv.get('entries') or []) + (inv.get('drives') or []):
    if e.get('dag'):
        named.add(e['dag'])
    for v in e.values():
        if isinstance(v, dict) and v.get('dag'):
            named.add(v['dag'])

problems = []
for name in sorted(n for n, tags in dags.items() if 'backup' in tags and n not in named):
    problems.append(f'unlisted: DAG {name} is tagged backup but no inventory entry names it')
for name in sorted(named - set(dags)):
    problems.append(f'missing: inventory names dag {name}, no dagu/dags file has that name')
for name in sorted(n for n in named & set(dags) if 'backup' not in dags[n]):
    problems.append(f'untagged: inventory names dag {name}, add `tags: [backup]` to it')

for p in problems:
    print(p)
backups = sum('backup' in t for t in dags.values())
print(f'{backups} backup DAGs, {len(named)} dags named in the inventory: '
      + ('in sync' if not problems else f'{len(problems)} problem(s)'))
sys.exit(1 if problems else 0)
PY
