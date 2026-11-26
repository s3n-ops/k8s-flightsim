Order per node: point the apt repository at the new series, upgrade
`kubeadm`, run `kubeadm upgrade plan` and `apply` (cp1 only) or
`kubeadm upgrade node` (all others), `drain`, upgrade `kubelet` and
`kubectl`, `systemctl restart kubelet`, `uncordon`.
