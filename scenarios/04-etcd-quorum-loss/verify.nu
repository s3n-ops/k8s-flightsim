use ../../scripts/lab.nu

# etcdctl on cp1, with the environment from /etc/profile.d/etcdctl.sh.
def etcdctl [arguments: string]: nothing -> record {
    lab node-try "cp1" $"sudo bash -lc 'source /etc/profile.d/etcdctl.sh && etcdctl ($arguments)'"
}

def main []: nothing -> nothing {
    let member_list = (etcdctl "member list -w json")
    let started = if $member_list.exit_code == 0 {
        $member_list.stdout
        | from json
        | get members
        | where {|member| ($member.name? | default "") != "" }
        | length
    } else { 0 }

    let healthy = ((etcdctl "endpoint health --cluster" | get exit_code) == 0)
    let flag_left = (
        (lab node-try "cp1" "sudo grep -q -- --force-new-cluster /etc/kubernetes/manifests/etcd.yaml" | get exit_code) == 0
    )

    let node_checks = (
        ["cp1" "cp2" "cp3"]
        | each {|node|
            let ready = (lab node-ready $node)
            lab check ($ready == "True") --success $"($node) is Ready" --failure $"($node) Ready=($ready)"
        }
    )

    let etcd_checks = [
        (lab check ($started == 3) --success "etcd has 3 started members" --failure $"etcd has ($started) started members")
        (lab check $healthy --success "all etcd endpoints healthy" --failure "not all etcd endpoints are healthy")
        (lab check (not $flag_left) --success "--force-new-cluster removed" --failure "--force-new-cluster is still in etcd.yaml")
    ]

    lab finish ...($etcd_checks ++ $node_checks)
}
