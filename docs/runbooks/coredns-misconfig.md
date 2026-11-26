# Cluster DNS is broken (CoreDNS)

**Area:** Network
**Scenario:** `scenarios/03-coredns-config`

## Symptom

Pods reach services by cluster IP, but not by name:

```
$ kubectl run t --rm -it --restart=Never --image=busybox:1.37 -- nslookup kubernetes.default
** server can't find kubernetes.default.svc.cluster.local: NXDOMAIN
```

## Diagnosis

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns     # are the pods running?
kubectl -n kube-system get svc kube-dns                 # ClusterIP 10.96.0.10
kubectl -n kube-system get endpointslices -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
kubectl -n kube-system get configmap coredns -o yaml    # read the Corefile
```

Inside a pod:

```bash
kubectl run t --rm -it --restart=Never --image=busybox:1.37 -- cat /etc/resolv.conf
# nameserver 10.96.0.10
# search default.svc.cluster.local svc.cluster.local cluster.local
```

If the pods run, the service exists and `resolv.conf` points to it, the
fault is in the configuration (Corefile).

## Cause

The Corefile says `kubernetes cluster.lokal` instead of
`kubernetes cluster.local`. CoreDNS now answers only names under
`cluster.lokal`. Everything under `cluster.local` goes to the upstream
resolver and ends with NXDOMAIN.

Other common causes:

| Cause | Hint |
|---|---|
| CoreDNS pods `Pending` | No CNI installed, nodes `NotReady` |
| CoreDNS `CrashLoopBackOff` with `Loop … detected` | Upstream resolver points to itself (`/etc/resolv.conf` on the node) |
| NetworkPolicy blocks UDP/TCP 53 | Allow egress to `kube-system` |

## Fix

```bash
kubectl -n kube-system edit configmap coredns
#   kubernetes cluster.local in-addr.arpa ip6.arpa {
kubectl -n kube-system rollout restart deployment coredns
```

The `reload` plugin picks up changes after about 30 seconds even without a
restart. The restart makes it immediate.

## Verify

```bash
kubectl run t --rm -it --restart=Never --image=busybox:1.37 -- nslookup kubernetes.default
```

## Prevention

- Manage the CoreDNS configuration through GitOps, with review.
- A blackbox probe that resolves a service name regularly.
