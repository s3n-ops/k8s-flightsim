# Back up and restore an etcd snapshot

**Area:** Backup
**Scenario:** `scenarios/06-etcd-snapshot`

## Problem

The whole cluster state (all objects, Secrets, configuration) lives in
etcd. Without a snapshot it is gone when all control plane nodes are lost.
Persistent volumes are **not** included; Velero covers those.

## Fix: take a snapshot

Endpoint and certificates are in the manifest:

```bash
just ssh cp1
sudo grep -E 'listen-client-urls|cert-file|key-file|trusted-ca-file' \
  /etc/kubernetes/manifests/etcd.yaml
```

```bash
sudo mkdir -p /var/backups/etcd
sudo ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

sudo etcdutl snapshot status /var/backups/etcd/snapshot.db -w table
```

## Fix: restore a snapshot (single node)

```bash
# 1. Restore into a NEW directory
sudo etcdutl snapshot restore /var/backups/etcd/snapshot.db \
  --data-dir /var/lib/etcd-restore

# 2. Point the etcd manifest at the new directory
sudo vi /etc/kubernetes/manifests/etcd.yaml
#   volumes:
#   - hostPath:
#       path: /var/lib/etcd-restore     # was /var/lib/etcd
#       type: DirectoryOrCreate
#     name: etcd-data

# 3. Wait until etcd and the API server have restarted
sudo crictl ps --name 'etcd|kube-apiserver'
```

With three control plane nodes: restore on one node, remove the others with
`kubeadm reset` and join them again (see
[etcd-quorum-loss.md](etcd-quorum-loss.md)).

## Common errors

| Error | Cause |
|---|---|
| `context deadline exceeded` | Wrong endpoint or missing certificates |
| `permission denied` when saving | Without `sudo`, the keys are readable by root only |
| Restore seems to have no effect | The manifest still points to the old data directory |

## Prevention

- Automated, encrypted snapshots stored outside the cluster.
- Practise the restore regularly. An untested backup is not a backup.
