use ../../scripts/lab.nu

def main []: nothing -> nothing {
    let ready = (lab node-ready "w2")
    let enabled = (lab node-try "w2" "systemctl is-enabled kubelet" | get stdout | str trim)
    (
        lab finish
            (lab check ($ready == "True") --success "w2 is Ready" --failure $"w2 Ready=($ready)")
            (lab check ($enabled == "enabled") --success "kubelet starts on boot" --failure $"kubelet is ($enabled)")
    )
}
