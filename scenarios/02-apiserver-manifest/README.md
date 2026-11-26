---
title: API server on cp1 does not start
type: incident
level: medium
runbook: docs/runbooks/apiserver-static-pod.md
---
## Situation

After a "small configuration change" on `cp1`, no API server runs there.
The cluster still answers, because `cp2` and `cp3` keep serving the API.

## Task

Find the fault and repair the API server on `cp1`. `kubectl` is of limited
help: the pod may not even exist in the Kubernetes API.
