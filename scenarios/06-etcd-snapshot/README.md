---
title: Take an etcd snapshot
type: drill
level: easy
runbook: docs/runbooks/etcd-snapshot.md
---
## Task

On `cp1`, take a snapshot of the etcd database at
`/var/backups/etcd/snapshot.db`. The certificates are listed in the
manifest of the etcd pod. Then check the snapshot with `etcdutl`.
