Test from a pod:
`kubectl run t --rm -it --restart=Never --image=busybox:1.37 -- nslookup kubernetes.default`.
The cluster DNS configuration is a ConfigMap in the namespace
`kube-system`.
