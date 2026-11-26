`sudo grep -E 'cert|key|listen-client' /etc/kubernetes/manifests/etcd.yaml`
shows endpoint and certificates. Then run `etcdctl snapshot save` with
`--endpoints`, `--cacert`, `--cert` and `--key`.
