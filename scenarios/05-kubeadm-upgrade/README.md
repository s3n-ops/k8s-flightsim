---
title: Cluster upgrade with kubeadm
type: drill
level: medium
runbook: docs/runbooks/kubeadm-upgrade.md
---
## Task

Upgrade the cluster to the next minor version (see
`kubernetes_upgrade_version` in `ansible/group_vars/all.yml`).

- First `cp1`, then `cp2` and `cp3`, then the workers one by one.
- Drain every node before its kubelet upgrade and uncordon it afterwards.
- Do it by hand, as in the exam. `ansible/upgrade.yml` is the reference
  solution.

Before you start: `just snapshot pre-upgrade`, so you can repeat the drill.
