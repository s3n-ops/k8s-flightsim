# etcd quorum lost

**Area:** Disaster recovery
**Scenario:** `scenarios/04-etcd-quorum-loss`

## Symptom

- `kubectl` hangs or answers `etcdserver: request timed out`.
- The VIP `10.17.3.10` is gone: kube-vip needs a working API server for its
  leader election.
- On the surviving node:

```bash
just ssh cp1
sudo crictl ps -a --name 'etcd|kube-apiserver'    # apiserver keeps restarting
sudo crictl logs $(sudo crictl ps -q --name etcd) 2>&1 | tail
# "is starting a new election", "lost leader", "no leader"
```

## Diagnosis

```bash
# etcdctl is preconfigured on the control plane nodes (/etc/profile.d/etcdctl.sh)
sudo -i
etcdctl member list -w table
etcdctl endpoint status --cluster -w table   # only cp1 answers
```

## Cause

etcd needs a majority (quorum): with 3 members at least 2. With only one
reachable member etcd accepts no writes and has no leader. The API server
cannot work without etcd.

| Members | Quorum | Survives the loss of |
|---|---|---|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |

## Fix

### Part 1: run cp1 on its own

The data on `cp1` is complete. etcd should form a new cluster from it with
this single member.

```bash
just ssh cp1
sudo -i

# 1. Back up the data directory
mv /etc/kubernetes/manifests/etcd.yaml /root/etcd.yaml   # stops etcd
sleep 20
cp -a /var/lib/etcd /root/etcd-data.bak

# 2. Set --force-new-cluster once
sed -i 's#    - --name=cp1#    - --name=cp1\n    - --force-new-cluster#' /root/etcd.yaml
cp /root/etcd.yaml /etc/kubernetes/manifests/etcd.yaml

# 3. Wait until etcd and the API server run
etcdctl member list -w table                 # only cp1 left
kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes

# 4. Remove the flag RIGHT AWAY
sed -i '/--force-new-cluster/d' /etc/kubernetes/manifests/etcd.yaml
```

> **Why step 4?** With the flag set, etcd resets the member list to a
> single member on every restart. At the latest after cp2 and cp3 rejoin,
> that destroys the cluster.

The VIP returns as soon as kube-vip on cp1 reaches the API server again.

### Part 2: add cp2 and cp3 again

```bash
# On the workstation: remove the old node objects, start the VMs
kubectl delete node cp2 cp3
virsh -c qemu:///system start k8s-flightsim-cp2
virsh -c qemu:///system start k8s-flightsim-cp3

# On cp2 and cp3: discard the old state
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
```

Rejoin with Ansible (`init` on cp1 is skipped because the cluster runs; a
new token and certificate key are created):

```bash
just bootstrap
```

Or by hand, as in the exam:

```bash
# on cp1
sudo kubeadm init phase upload-certs --upload-certs   # last line = certificate key
sudo kubeadm token create --print-join-command

# on cp2 (cp3 the same with 10.17.3.13)
sudo <join-command> --control-plane --certificate-key <key> \
  --apiserver-advertise-address 10.17.3.12
# copy the kube-vip manifest from cp1
ssh 10.17.3.11 sudo cat /etc/kubernetes/manifests/kube-vip.yaml \
  | sudo tee /etc/kubernetes/manifests/kube-vip.yaml >/dev/null
```

## Verify

```bash
sudo -i etcdctl member list -w table            # 3 x started
sudo -i etcdctl endpoint health --cluster       # 3 x healthy
kubectl get nodes                               # cp1..cp3 Ready
```

## Variant: cp1 is lost as well

Then only a snapshot helps (see [etcd-snapshot.md](etcd-snapshot.md)):
`etcdutl snapshot restore` on a freshly built control plane node, then
join the other nodes again. Without a snapshot the cluster state is lost,
and only GitOps (Argo CD) plus Velero bring the objects back.

## Prevention

- Regular etcd snapshots outside the cluster.
- Spread control plane nodes over separate hosts or failure domains.
- Alert on `etcd_server_has_leader == 0` and
  `etcd_server_leader_changes_seen_total`.
