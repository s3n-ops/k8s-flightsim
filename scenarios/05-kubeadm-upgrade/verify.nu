use ../../scripts/lab.nu

def main []: nothing -> nothing {
    let target = (
        open ($lab.LAB_ROOT | path join "ansible" "group_vars" "all.yml")
        | get kubernetes_upgrade_version
    )
    let version_json = (^kubectl version -o json)
    let server = ($version_json | from json | get serverVersion.gitVersion)
    let server_check = (
        lab check ($server starts-with $"v($target).")
            --success $"API server ($server)"
            --failure $"API server ($server), expected v($target).x"
    )

    let nodes_json = (^kubectl get nodes -o json)
    let node_checks = (
        $nodes_json
        | from json
        | get items
        | each {|node|
            let name = $node.metadata.name
            let version = $node.status.nodeInfo.kubeletVersion
            let cordoned = ($node.spec.unschedulable? | default false)
            (
                lab check (($version starts-with $"v($target).") and not $cordoned)
                    --success $"($name) kubelet ($version)"
                    --failure $"($name) kubelet ($version) unschedulable=($cordoned)"
            )
        }
    )

    lab finish ...([$server_check] ++ $node_checks)
}
