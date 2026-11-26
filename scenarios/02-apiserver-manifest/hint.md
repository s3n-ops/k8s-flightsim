The API server is a static pod. Its definition lives on the node in
`/etc/kubernetes/manifests/`. `sudo crictl ps -a` shows running and crashed
containers, `sudo crictl logs <id>` their logs.
