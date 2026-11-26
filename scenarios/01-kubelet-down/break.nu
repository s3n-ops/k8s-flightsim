use ../../scripts/lab.nu

def main []: nothing -> nothing {
    lab node-run "w2" "sudo systemctl disable --now kubelet" | ignore
}
