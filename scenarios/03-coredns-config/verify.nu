use ../../scripts/lab.nu

def main []: nothing -> nothing {
    let pod = $"flightsim-dnscheck-(random int 1000..9999)"
    let result = (
        ^kubectl run $pod
            --rm -i --quiet --restart=Never --image=busybox:1.37
            --command -- nslookup kubernetes.default.svc.cluster.local
        | complete
    )
    (
        lab finish
            (lab check ($result.exit_code == 0) --success "kubernetes.default.svc.cluster.local resolves" --failure "name resolution inside the cluster fails")
    )
}
