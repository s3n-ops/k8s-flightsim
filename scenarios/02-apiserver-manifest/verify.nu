use ../../scripts/lab.nu

const MANIFEST_FILE_PATH = "/etc/kubernetes/manifests/kube-apiserver.yaml"

def main []: nothing -> nothing {
    let grep = $"sudo grep -q -- '--etcd-servers=https://127.0.0.1:2379' ($MANIFEST_FILE_PATH)"
    let fixed = ((lab node-try "cp1" $grep | get exit_code) == 0)
    let url = $"https://(lab node-ip cp1):6443/readyz"
    let ready = (try { http get --insecure --max-time 5sec $url } catch { "no answer" })
    (
        lab finish
            (lab check $fixed --success "manifest points at the local etcd" --failure "manifest still has a wrong --etcd-servers")
            (lab check ($ready == "ok") --success "API server on cp1 is ready" --failure $"($url): ($ready)")
    )
}
