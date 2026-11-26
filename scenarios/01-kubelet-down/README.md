---
title: Worker reports NotReady
type: incident
level: easy
runbook: docs/runbooks/node-notready-kubelet.md
---
## Situation

Monitoring reports: node `w2` is `NotReady`. After a few minutes, pods on
`w2` are no longer restarted.

## Task

Bring `w2` back to `Ready`. The node must also become `Ready` on its own
after a reboot of the VM.
