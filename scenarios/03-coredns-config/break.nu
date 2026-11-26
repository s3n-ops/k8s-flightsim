use ../../scripts/lab.nu

def main []: nothing -> nothing {
    let corefile = (lab exec-checked "kubectl" "-n" "kube-system" "get" "configmap" "coredns" "-o" "yaml")
    let broken = ($corefile | str replace "kubernetes cluster.local " "kubernetes cluster.lokal ")
    let result = ($broken | ^kubectl apply -f - | complete)
    if $result.exit_code != 0 {
        error make --unspanned {msg: $"kubectl apply failed: ($result.stderr | str trim)"}
    }
    lab exec-checked "kubectl" "-n" "kube-system" "rollout" "restart" "deployment" "coredns" | ignore
    lab exec-checked "kubectl" "-n" "kube-system" "rollout" "status" "deployment" "coredns" "--timeout=120s" | ignore
}
