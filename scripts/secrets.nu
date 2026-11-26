# Creates the Kubernetes Secrets that the GitOps repository only references.
# Values are generated once and kept in the data directory outside the
# repository (~/.local/share/k8s-flightsim/secrets), so a rebuilt cluster
# gets the same credentials.

use lab.nu

def secrets-path []: nothing -> string { lab data-dir | path join "secrets" }

# Path of a stored value. Generates a random value on first use.
def value-file-path [name: path]: nothing -> string {
    let file_path = (secrets-path | path join $name)
    if not ($file_path | path exists) or (open --raw $file_path | is-empty) {
        random chars --length 32 | save --force $file_path
        ^chmod "600" $file_path
    }
    $file_path
}

# Applies a rendered manifest and fails with kubectl's message on error.
def kubectl-apply [manifest: string, what: string]: nothing -> nothing {
    let result = ($manifest | ^kubectl apply -f - | complete)
    if $result.exit_code != 0 {
        lab fail $what
        error make --unspanned {msg: $"kubectl apply failed for ($what): ($result.stderr | str trim)"}
    }
}

# Creates or updates a Secret. Every manifest is rendered first: in a
# pipeline only the last external command's exit code counts.
def apply-secret [
    secret: record<namespace: string, name: string, sources: list<string>>
    --type: string = "Opaque"  # Secret type, e.g. kubernetes.io/tls
]: nothing -> nothing {
    let namespace_yaml = (^kubectl create namespace $secret.namespace --dry-run=client -o yaml)
    kubectl-apply $namespace_yaml $"namespace ($secret.namespace)"
    let secret_yaml = (
        ^kubectl -n $secret.namespace create secret generic $secret.name ...$secret.sources
            $"--type=($type)" --dry-run=client -o yaml
    )
    kubectl-apply $secret_yaml $"secret ($secret.namespace)/($secret.name)"
    lab pass $"secret ($secret.namespace)/($secret.name)"
}

# Creates all Secrets the GitOps repository references.
def main []: nothing -> nothing {
    lab info "waiting for the API server"
    lab wait-api
    mkdir (secrets-path)
    ^chmod "700" (lab data-dir) (secrets-path)

    # Values are passed as files, so they never show up in the process list.
    apply-secret {
        namespace: "miniflux"
        name: "miniflux-admin"
        sources: [
            "--from-literal=ADMIN_USERNAME=admin"
            $"--from-file=ADMIN_PASSWORD=(value-file-path miniflux-admin-password)"
        ]
    }

    apply-lab-ca
    apply-velero

    lab info $"credentials are stored in (secrets-path)"
}

# Intermediate CA for the cert-manager ClusterIssuer lab-ca. tls.crt holds
# intermediate and root, so issued certificates carry the full chain. The
# root key stays on the host.
def apply-lab-ca []: nothing -> nothing {
    let pki_dir = (lab data-dir | path join "pki")
    let cert = ($pki_dir | path join "intermediate-ca.crt")
    let key = ($pki_dir | path join "intermediate-ca.key")
    let root = ($pki_dir | path join "root-ca.crt")
    if not ($key | path exists) {
        lab info "no lab PKI yet, skipping the CA secret (run: just pki init)"
        return
    }
    let runtime_dir = ($env.XDG_RUNTIME_DIR? | default "/tmp")
    let chain = ($runtime_dir | path join $"k8s-flightsim-chain-(random chars --length 8).crt")
    (open --raw $cert) + (open --raw $root) | save $chain
    try {
        apply-secret --type "kubernetes.io/tls" {
            namespace: "cert-manager"
            name: "lab-intermediate-ca"
            sources: [$"--from-file=tls.crt=($chain)" $"--from-file=tls.key=($key)"]
        }
    } catch {|error|
        rm --force $chain
        error make --unspanned {msg: $error.msg}
    }
    rm --force $chain
}

# S3 credentials and Kopia repository password for Velero. The backup
# target (lab s3-start) reads the same S3 keys. The repository password
# encrypts the volume backups. A rebuilt cluster needs the same password
# to restore them.
def apply-velero []: nothing -> nothing {
    let access_key = (open --raw (value-file-path velero-s3-access-key) | str trim)
    let secret_key = (open --raw (value-file-path velero-s3-secret-key) | str trim)
    let runtime_dir = ($env.XDG_RUNTIME_DIR? | default "/tmp")
    let cloud = ($runtime_dir | path join $"k8s-flightsim-velero-(random chars --length 8)")
    $"[default]\naws_access_key_id=($access_key)\naws_secret_access_key=($secret_key)\n"
    | save $cloud
    ^chmod "600" $cloud
    try {
        apply-secret {
            namespace: "velero"
            name: "velero-s3"
            sources: [$"--from-file=cloud=($cloud)"]
        }
    } catch {|error|
        rm --force $cloud
        error make --unspanned {msg: $error.msg}
    }
    rm --force $cloud
    apply-secret {
        namespace: "velero"
        name: "velero-repo-credentials"
        sources: [$"--from-file=repository-password=(value-file-path velero-repo-password)"]
    }
}
