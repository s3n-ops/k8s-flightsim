# Stops and starts the lab VMs. Nothing is deleted.
#
#   power.nu status  VM and network state, nodes and system pods if the API answers
#   power.nu stop    shut down workers, then control plane, stop the network
#   power.nu start   start network, control plane, workers, wait for the API

use lab.nu

# Shows the status of the lab.
def main []: nothing -> nothing { main status }

# Shows VM and network state, then nodes and system pods if the API answers.
def "main status" []: nothing -> nothing {
    let domains = (
        lab domains
        | each {|domain| {domain: $domain, state: (lab domain-state $domain)} }
    )
    if ($domains | is-empty) {
        lab info $"no (lab prefix)-* domains found, the lab is not built"
        return
    }
    print $domains
    print $"network (lab prefix): (if (lab network-active) { 'active' } else { 'inactive' })"
    print $"backup target (lab s3-unit): (lab s3-state)"

    if ($domains | where state == "running" | is-empty) {
        lab info "cluster is stopped (just start)"
        return
    }
    if not (lab api-ready) {
        lab info "API server not reachable, VMs may still be booting"
        return
    }
    ^kubectl get nodes -o wide
    ^kubectl get pods -n kube-system -o wide
}

# Shuts the cluster down cleanly.
def "main stop" []: nothing -> nothing {
    lab stop-cluster
    lab pass "cluster stopped"
}

# Starts the cluster and waits until the API server answers.
def "main start" []: nothing -> nothing {
    lab start-cluster
    lab info "waiting for the API server"
    lab wait-api
    lab pass "cluster started"
}
