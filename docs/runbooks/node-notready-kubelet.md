# Node NotReady: kubelet is not running

**Area:** Node
**Scenario:** `scenarios/01-kubelet-down`

## Symptom

```
$ kubectl get nodes
NAME   STATUS     ROLES    AGE   VERSION
w2     NotReady   <none>   2d    v1.36.x
```

After about 5 minutes the node gets the taint
`node.kubernetes.io/unreachable`. Its pods are then restarted on other
nodes, as long as a controller (Deployment, StatefulSet) manages them.

## Diagnosis

```bash
kubectl describe node w2 | grep -A8 Conditions
# Status "Unknown", reason "NodeStatusUnknown":
# "Kubelet stopped posting node status."

just ssh w2
systemctl status kubelet          # inactive (dead)?
systemctl is-enabled kubelet      # disabled?
journalctl -u kubelet -n 50       # errors on the last start?
systemctl status containerd       # check the runtime as well
```

## Cause

The kubelet reports the node status to the API server. If it does not run,
the reports stop and the node lifecycle controller marks the node
`Unknown`/`NotReady`. Common reasons: service stopped or disabled, swap
enabled, wrong cgroup driver, containerd not running, expired kubelet
certificate.

## Fix

```bash
sudo systemctl enable --now kubelet
journalctl -u kubelet -f          # until the node registers again
```

If the kubelet does not start, `journalctl -u kubelet` says why. Typical
messages:

| Message | Fix |
|---|---|
| `running with swap on is not supported` | `sudo swapoff -a`, comment out swap in `/etc/fstab` |
| `failed to run Kubelet: misconfiguration: kubelet cgroup driver` | `SystemdCgroup = true` in `/etc/containerd/config.toml`, restart containerd |
| `container runtime is down` | `sudo systemctl restart containerd` |
| `x509: certificate has expired` | `kubeadm certs check-expiration` on the control plane |

## Verify

```bash
kubectl get node w2               # Ready
systemctl is-enabled kubelet      # enabled
```

## Prevention

- Alert on `kube_node_status_condition{condition="Ready",status="true"} == 0`.
- Change node configuration only through Ansible, never by hand.
