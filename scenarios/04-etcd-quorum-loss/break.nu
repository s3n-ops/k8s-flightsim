use ../../scripts/lab.nu

def main []: nothing -> nothing {
    for node in ["cp2" "cp3"] {
        let domain = $"(lab prefix)-($node)"
        lab virsh "destroy" $domain | ignore
        lab info $"($domain) powered off"
    }
}
