# Cluster upgrade with kubeadm

**Area:** Operations
**Scenario:** `scenarios/05-kubeadm-upgrade`
**Reference solution:** `ansible/upgrade.yml`

## Problem

The Kubernetes version should go up by one minor version without workload
downtime. kubeadm allows only **one** minor step per upgrade, and a kubelet
must never be newer than the API server.

## Fix

Example: 1.36 → 1.37. Order: first control plane node, other control plane
nodes, then workers. One node at a time.

### 1. First control plane node (cp1)

```bash
just ssh cp1
# Point the package repository at the new series
sudo sed -i 's#v1.36#v1.37#g' /etc/apt/sources.list.d/kubernetes.sources
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.asc
sudo apt-get update
apt-cache madison kubeadm | head -3          # exact version, e.g. 1.37.2-1.1

sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.37.2-1.1
sudo apt-mark hold kubeadm

sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.37.2
```

### 2. kubelet on cp1

```bash
kubectl drain cp1 --ignore-daemonsets --delete-emptydir-data
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.37.2-1.1 kubectl=1.37.2-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon cp1
```

### 3. cp2, cp3 and the workers

As above, but instead of `kubeadm upgrade apply` only:

```bash
sudo kubeadm upgrade node
```

`drain` and `uncordon` run from any machine with a kubeconfig (workstation
or cp1), not necessarily on the node itself.

## Verify

```bash
kubectl get nodes                  # all VERSION v1.37.x, none SchedulingDisabled
kubectl version                    # server v1.37.x
```

## Common errors

| Error | Cause |
|---|---|
| `kubeadm upgrade apply` refuses: "Specified version to upgrade to … is too high" | More than one minor step |
| `apt` finds no 1.37 packages | Repository still on `v1.36` |
| Drain hangs | A PodDisruptionBudget allows no disruption; `kubectl get pdb -A` |
| Node stays `SchedulingDisabled` | `uncordon` forgotten |

## Prevention

- Take `just snapshot pre-upgrade` first (in production: an etcd snapshot).
- Check the release notes for removed APIs (`kubectl deprecations`,
  `pluto`).
