# Runbooks

Common Kubernetes problems, each in the same format:
**Symptom → Diagnosis → Cause → Fix → Verify → Prevention**.
Every runbook links to a scenario that reproduces the problem in the lab.

| Runbook | Area | Scenario |
|---|---|---|
| [Node NotReady: kubelet is not running](node-notready-kubelet.md) | Node | `01-kubelet-down` |
| [API server does not start (static pod)](apiserver-static-pod.md) | Control plane | `02-apiserver-manifest` |
| [Cluster DNS is broken (CoreDNS)](coredns-misconfig.md) | Network | `03-coredns-config` |
| [etcd quorum lost](etcd-quorum-loss.md) | Disaster recovery | `04-etcd-quorum-loss` |
| [Cluster upgrade with kubeadm](kubeadm-upgrade.md) | Operations | `05-kubeadm-upgrade` |
| [Back up and restore an etcd snapshot](etcd-snapshot.md) | Backup | `06-etcd-snapshot` |

New runbook: copy [`_template.md`](_template.md).
