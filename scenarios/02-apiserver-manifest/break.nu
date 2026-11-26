use ../../scripts/lab.nu

const MANIFEST_FILE_PATH = "/etc/kubernetes/manifests/kube-apiserver.yaml"

def main []: nothing -> nothing {
    let command = $"sudo sed -i 's#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://127.0.0.1:2399#' ($MANIFEST_FILE_PATH)"
    lab node-run "cp1" $command | ignore
}
