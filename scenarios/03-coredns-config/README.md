---
title: Services cannot be reached by name
type: incident
level: medium
runbook: docs/runbooks/coredns-misconfig.md
---
## Situation

Applications report `could not resolve host`. Connections to a service's
cluster IP work, connections by name do not.

## Task

Restore name resolution in the cluster.
`kubernetes.default.svc.cluster.local` must resolve from every pod.
