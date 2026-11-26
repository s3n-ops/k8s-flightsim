# Cluster-wide libvirt snapshots.
#
#   snapshot.nu create <name>   shut down all nodes, snapshot, start again
#   snapshot.nu revert <name>   power off all nodes, revert, start again
#   snapshot.nu delete <name>
#   snapshot.nu list
#   snapshot.nu purge           delete every snapshot (needed before destroy)
#
# All nodes are snapshotted while powered off, so etcd sees one consistent
# point in time on every member.

use lab.nu

# All lab domains. Empty when the lab is not built.
def lab-domains []: nothing -> list<string> {
    let domains = (lab domains)
    if ($domains | is-empty) { lab info $"no (lab prefix)-* domains found" }
    $domains
}

def has-snapshot [domain: string, name: string]: nothing -> bool {
    (^virsh "-c" (lab libvirt-uri) "snapshot-info" $domain "--snapshotname" $name | complete).exit_code == 0
}

def snapshots [domain: string]: nothing -> list<string> {
    lab virsh "snapshot-list" $domain "--name" | lines | where {|line| $line != "" }
}

# Lists the snapshots of all nodes.
def main []: nothing -> nothing { main list }

# Shuts the cluster down, snapshots every node and starts it again.
def "main create" [
    name: string  # snapshot name, e.g. base
]: nothing -> nothing {
    let domains = (lab-domains)
    let taken = ($domains | where {|domain| has-snapshot $domain $name })
    if ($taken | is-not-empty) {
        lab fail $"snapshot '($name)' exists on ($taken | str join ', '), delete it first"
        exit 1
    }

    lab info "trimming free space so the snapshot stays small"
    for domain in $domains {
        let result = (lab node-try (lab node-name $domain) "sudo fstrim -a")
        if $result.exit_code != 0 { lab info $"($domain): fstrim skipped" }
    }

    lab stop-cluster

    for domain in $domains {
        (
            lab virsh "snapshot-create-as" $domain
                "--name" $name
                "--description" $"k8s-flightsim ($name)"
                "--atomic"
        ) | ignore
        lab pass $"($domain): snapshot '($name)'"
    }

    lab start-cluster
    lab info "waiting for the API server"
    lab wait-api
}

# Powers all nodes off, reverts them and starts them again.
def "main revert" [
    name: string  # snapshot name
]: nothing -> nothing {
    let domains = (lab-domains)
    let missing = ($domains | where {|domain| not (has-snapshot $domain $name) })
    if ($missing | is-not-empty) {
        lab fail $"no snapshot '($name)' on ($missing | str join ', ')"
        exit 1
    }

    for domain in $domains {
        if (lab domain-state $domain) != "shut off" {
            lab virsh "destroy" $domain | ignore
        }
        lab virsh "snapshot-revert" $domain "--snapshotname" $name | ignore
        lab pass $"($domain): reverted to '($name)'"
    }

    lab start-cluster
    lab info "waiting for the API server"
    lab wait-api
}

# Deletes one snapshot on every node.
def "main delete" [
    name: string  # snapshot name
]: nothing -> nothing {
    for domain in (lab-domains) {
        if (has-snapshot $domain $name) {
            lab virsh "snapshot-delete" $domain "--snapshotname" $name | ignore
        }
        lab pass $"($domain): '($name)' deleted"
    }
}

# Deletes every snapshot on every node.
def "main purge" []: nothing -> nothing {
    for domain in (lab-domains) {
        for snapshot in (snapshots $domain) {
            lab virsh "snapshot-delete" $domain "--snapshotname" $snapshot | ignore
            lab pass $"($domain): '($snapshot)' deleted"
        }
    }
}

# Lists the snapshots of all nodes.
def "main list" []: nothing -> nothing {
    lab-domains
    | each {|domain| {domain: $domain, snapshots: (snapshots $domain | str join ", ")} }
    | print
}
