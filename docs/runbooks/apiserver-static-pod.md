# API server does not start (static pod)

**Area:** Control plane
**Scenario:** `scenarios/02-apiserver-manifest`

## Symptom

- Single control plane: `kubectl` reports
  `The connection to the server … was refused`.
- HA cluster (as here): `kubectl` keeps working through the VIP, but
  `kubectl -n kube-system get pods` shows `kube-apiserver-cp1` in
  `CrashLoopBackOff` or not at all.

## Diagnosis

The Kubernetes API helps only a little, so go to the node:

```bash
just ssh cp1
sudo crictl ps -a --name kube-apiserver     # Exited, many restarts?
sudo crictl logs <container-id> 2>&1 | tail -20
journalctl -u kubelet -n 50 | grep -i apiserver
```

In the scenario the logs show repeated connection errors to etcd:

```
grpc: addrConn.createTransport failed to connect to {Addr: "127.0.0.1:2399" …
connection refused
```

Then check the manifest:

```bash
sudo grep -n -- '--etcd' /etc/kubernetes/manifests/kube-apiserver.yaml
```

## Cause

With kubeadm, the control plane components are **static pods**: the kubelet
reads `/etc/kubernetes/manifests/*.yaml` directly and starts the
containers itself. A typo in a flag (here the etcd port `2399` instead of
`2379`) makes the container crash right away.

## Fix

```bash
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
#   --etcd-servers=https://127.0.0.1:2379
```

The kubelet notices the change after a few seconds and restarts the pod.
No `kubectl apply` is needed.

> **Important:** Never keep backup copies in `manifests/`. The kubelet
> starts every `.yaml` file in there as a pod.

## Verify

```bash
sudo crictl ps --name kube-apiserver        # Running
curl -k https://10.17.3.11:6443/readyz      # ok
```

## Prevention

- Change flags through the kubeadm configuration (`ClusterConfiguration`)
  instead of editing manifests by hand.
- Before a manual change, keep a copy outside `manifests/`.
- With three control plane nodes the cluster stays reachable when one API
  server fails. This scenario shows exactly that.
