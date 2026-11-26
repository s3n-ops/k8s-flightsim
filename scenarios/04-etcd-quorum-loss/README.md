---
title: Two control plane nodes destroyed
type: disaster
level: hard
runbook: docs/runbooks/etcd-quorum-loss.md
---
## Situation

`cp2` and `cp3` failed in the data center. Their disks are considered
lost. etcd has only 1 of 3 members left and no quorum. The Kubernetes API
does not answer, not even through the VIP `10.17.3.10`.

## Rules

- Treat `cp2` and `cp3` as new, empty machines. You may start the VMs
  again, but you must reset them with `kubeadm reset` before they rejoin
  the cluster.
- The workloads and objects in the cluster must survive.

## Task

1. Make the cluster work again with `cp1` alone.
2. Add `cp2` and `cp3` back as control plane nodes.
3. At the end, etcd has three healthy members again.
