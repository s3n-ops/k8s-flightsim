etcd can restart a cluster from the data of a single member: flag
`--force-new-cluster`. etcd runs as a static pod. Remember to remove the
flag afterwards. To rejoin you need a fresh token and a certificate key
(`kubeadm init phase upload-certs --upload-certs`).
