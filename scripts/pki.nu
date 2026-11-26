# Two-tier lab PKI for *.k8s-flightsim.internal.
#
#   pki.nu init                  root CA (10 years) and intermediate CA (1 year)
#   pki.nu rotate-intermediate   new intermediate CA, the old one is archived
#   pki.nu status                subjects, expiry, constraints, chain check
#   pki.nu trust                 trust the root CA on this host (mkcert)
#   pki.nu untrust               remove it again (mkcert)
#
# This script never writes to a trust store itself; mkcert does, with a
# CAROOT that holds only the root certificate and never a key.
#
# The root key exists on disk only encrypted with age. For signing it is
# decrypted into memory and piped to openssl; it is never written to a file,
# so an interrupted run (Ctrl+C) cannot leave it behind. The
# intermediate key stays unencrypted: cert-manager in the cluster needs it.
# Both CAs carry name constraints, so they can only sign names under the
# lab domain, never an IP address or any other domain.

use lab.nu

const DOMAIN = "k8s-flightsim.internal"
const ROOT_DAYS = 3650
const INTERMEDIATE_DAYS = 365

def pki-dir []: nothing -> string { lab data-dir | path join "pki" }

# Settings from ~/.config/k8s-flightsim/pki.toml (skeleton: conf/pki.skel.toml).
def pki-config []: nothing -> record {
    let file = (lab config-dir | path join "pki.toml")
    let defaults = {age_recipients: [], age_recipients_file: "", age_identity_file: ""}
    if ($file | path exists) { $defaults | merge (open $file) } else { $defaults }
}

# age arguments that select how the root key is encrypted: recipients from
# the config, or a passphrase when none are set.
def encrypt-args []: nothing -> list<string> {
    let config = (pki-config)
    let inline = ($config.age_recipients | where {|key| ($key | str trim) != "" })
    for key in $inline {
        if not (($key starts-with "age1") or ($key starts-with "ssh-")) {
            error make --unspanned {msg: $"pki.toml: ($key | str substring 0..11)... is not an age or SSH public key"}
        }
    }
    let file_args = if ($config.age_recipients_file | is-empty) { [] } else {
        let path = ($config.age_recipients_file | path expand)
        if not ($path | path exists) {
            error make --unspanned {msg: $"pki.toml: age_recipients_file ($path) does not exist"}
        }
        ["--recipients-file" $path]
    }
    let recipient_args = ($inline | each {|key| ["--recipient" $key] } | flatten)
    let args = ($recipient_args ++ $file_args)
    if ($args | is-empty) { ["--passphrase"] } else { $args }
}

# age arguments to decrypt the root key: the configured identity, or none
# (age then asks for the passphrase).
def decrypt-args []: nothing -> list<string> {
    let identity = (pki-config).age_identity_file
    if ($identity | is-empty) { [] } else { ["--identity" ($identity | path expand)] }
}
def root-cert []: nothing -> string { pki-dir | path join "root-ca.crt" }
def root-key []: nothing -> string { pki-dir | path join "root-ca.key.age" }
def intermediate-cert []: nothing -> string { pki-dir | path join "intermediate-ca.crt" }
def intermediate-key []: nothing -> string { pki-dir | path join "intermediate-ca.key" }

# Extension sections for both CA levels. Name constraints are critical:
# clients that do not understand them must reject the certificate.
def extensions [path_length: int]: nothing -> string {
    [
        "[ca]"
        $"basicConstraints = critical, CA:TRUE, pathlen:($path_length)"
        "keyUsage = critical, keyCertSign, cRLSign"
        "subjectKeyIdentifier = hash"
        "authorityKeyIdentifier = keyid:always"
        $"nameConstraints = critical, permitted;DNS:($DOMAIN), excluded;IP:0.0.0.0/0.0.0.0, excluded;IP:0:0:0:0:0:0:0:0/0:0:0:0:0:0:0:0"
    ]
    | str join "\n"
}

def runtime-dir []: nothing -> string { $env.XDG_RUNTIME_DIR? | default "/tmp" }

# Removes leftovers of an interrupted run (Ctrl+C skips the cleanup):
# working directories on tmpfs and unfinished *.tmp files. Neither ever
# holds the plaintext root key, which only exists in memory.
def remove-leftovers []: nothing -> nothing {
    let stale = (
        (glob ((runtime-dir) | path join "k8s-flightsim-pki-*"))
        ++ (glob ((pki-dir) | path join "*.tmp"))
    )
    if ($stale | is-not-empty) {
        lab info $"removing ($stale | length) leftovers of an interrupted run"
        rm --recursive --force ...$stale
    }
}

# Private working directory for non-secret files (extensions, requests).
def scratch-dir []: nothing -> string {
    let dir = ((runtime-dir) | path join $"k8s-flightsim-pki-(random chars --length 8)")
    mkdir $dir
    ^chmod "700" $dir
    $dir
}

# Runs a command with `input` on stdin and fails on a non-zero exit. Keys
# reach openssl and age this way, as /dev/stdin, never as a file.
def piped [input: string, command: string, ...args: string]: nothing -> string {
    let result = ($input | ^$command ...$args | complete)
    if $result.exit_code != 0 {
        error make --unspanned {msg: $"`([$command ...$args] | str join ' ')` failed: ($result.stderr | str trim)"}
    }
    $result.stdout
}

def new-ec-key []: nothing -> string {
    lab exec-checked "openssl" "genpkey" "-algorithm" "EC" "-pkeyopt" "ec_paramgen_curve:P-256"
}

# Signs a new intermediate CA. Writes *.tmp files and renames them at the
# end, so an interrupted run leaves no half-finished CA behind.
def sign-intermediate [root_key: string]: nothing -> nothing {
    let dir = (scratch-dir)
    let ext_file = ($dir | path join "intermediate.ext")
    let csr_file = ($dir | path join "intermediate-ca.csr")
    let key_tmp = $"(intermediate-key).tmp"
    let cert_tmp = $"(intermediate-cert).tmp"
    extensions 0 | save $ext_file

    new-ec-key | save --force $key_tmp
    ^chmod "600" $key_tmp
    (
        lab exec-checked "openssl" "req" "-new" "-key" $key_tmp "-out" $csr_file
            "-subj" $"/O=k8s-flightsim/CN=k8s-flightsim Intermediate CA (date now | format date '%Y-%m-%d')"
    ) | ignore
    (
        piped $root_key "openssl" "x509" "-req" "-in" $csr_file "-out" $cert_tmp
            "-CA" (root-cert) "-CAkey" "/dev/stdin" "-set_serial" $"0x(random chars --length 16 | encode hex)"
            "-days" ($INTERMEDIATE_DAYS | into string) "-sha256"
            "-extfile" $ext_file "-extensions" "ca"
    ) | ignore
    rm --recursive --force $dir

    mv --force $key_tmp (intermediate-key)
    mv --force $cert_tmp (intermediate-cert)
    lab pass $"intermediate CA: (intermediate-cert)"
}

# Decrypts the root key into memory.
def decrypt-root-key []: nothing -> string {
    lab info "decrypting the root key"
    lab exec-checked "age" "--decrypt" ...(decrypt-args) (root-key)
}

# Creates the root CA and the first intermediate CA. Existing keys are kept.
def "main init" []: nothing -> nothing {
    mkdir (pki-dir)
    ^chmod "700" (lab data-dir) (pki-dir)
    remove-leftovers

    if not (root-key | path exists) {
        # A root certificate without its key is left over from an older,
        # interrupted run. It was never usable, so it is replaced.
        if (root-cert | path exists) {
            lab info "removing a root certificate without key"
            rm (root-cert)
        }
        # Read the config first: a bad recipient must fail before any key exists.
        let age_args = (encrypt-args)
        let root_key = (new-ec-key)
        let dir = (scratch-dir)
        let ext_file = ($dir | path join "root.ext")
        extensions 1 | save $ext_file
        (
            piped $root_key "openssl" "req" "-x509" "-new" "-key" "/dev/stdin" "-out" $"(root-cert).tmp"
                "-subj" "/O=k8s-flightsim/CN=k8s-flightsim Root CA"
                "-days" ($ROOT_DAYS | into string) "-sha256"
                "-config" $ext_file "-extensions" "ca"
        ) | ignore
        rm --recursive --force $dir

        if $age_args == ["--passphrase"] {
            lab info "no age recipients in pki.toml: choose a passphrase and keep it in your password manager"
        } else {
            lab info "encrypting the root key to the age recipients from pki.toml"
        }
        piped $root_key "age" ...$age_args "--output" $"(root-key).tmp" | ignore
        ^chmod "600" $"(root-key).tmp"
        mv --force $"(root-key).tmp" (root-key)
        mv --force $"(root-cert).tmp" (root-cert)
        lab pass $"root CA: (root-cert)"

        if not (intermediate-key | path exists) { sign-intermediate $root_key }
        return
    }

    lab info $"root CA exists, kept: (root-cert)"
    if (intermediate-key | path exists) {
        lab info $"intermediate CA exists, kept: (intermediate-cert)"
    } else {
        sign-intermediate (decrypt-root-key)
    }
}

# Archives the current intermediate CA and signs a new one.
def "main rotate-intermediate" []: nothing -> nothing {
    if not (root-key | path exists) {
        lab fail "no root CA, run: just pki init"
        exit 1
    }
    remove-leftovers
    # Decrypt first: a wrong passphrase must not leave the lab without an
    # active intermediate CA.
    let root_key = (decrypt-root-key)
    if (intermediate-cert | path exists) {
        let stamp = (date now | format date "%Y%m%dT%H%M%S")
        cp (intermediate-cert) (pki-dir | path join $"intermediate-ca-($stamp).crt")
        cp --preserve [mode] (intermediate-key) (pki-dir | path join $"intermediate-ca-($stamp).key")
        lab info $"old intermediate CA archived with suffix ($stamp)"
    }
    sign-intermediate $root_key
}

# Shows both CAs and checks the chain.
def "main status" []: nothing -> nothing {
    for cert in [(root-cert) (intermediate-cert)] {
        if not ($cert | path exists) {
            lab fail $"missing ($cert), run: just pki init"
            continue
        }
        let text = (lab exec-checked "openssl" "x509" "-in" $cert "-noout" "-subject" "-issuer" "-enddate" "-ext" "basicConstraints,nameConstraints")
        print $"(ansi cyan)($cert | path basename)(ansi reset)"
        print ($text | str trim | lines | each {|line| $"  ($line | str trim)" } | str join "\n")
    }
    let verify = (^openssl verify -CAfile (root-cert) (intermediate-cert) | complete)
    lab check ($verify.exit_code == 0) --success "chain verifies" --failure $"chain broken: ($verify.stderr | str trim)" | ignore
    let mode = (ls --long (root-key) | get -o 0.mode | default "missing")
    lab check ($mode == "rw-------") --success "root key is age-encrypted, mode 600" --failure $"root key mode is ($mode)" | ignore
}

# CAROOT for mkcert: a copy of the root certificate, nothing else. With
# rootCA.pem present and no rootCA-key.pem, mkcert can install the root but
# never issue certificates. Without rootCA.pem it would create a CA of its
# own, so the file is checked before every call.
def mkcert-caroot []: nothing -> string {
    if not (root-cert | path exists) {
        error make --unspanned {msg: "no root CA, run: just pki init"}
    }
    if (which mkcert | is-empty) {
        error make --unspanned {msg: "mkcert not found, see https://github.com/FiloSottile/mkcert"}
    }
    let dir = (pki-dir | path join "mkcert")
    mkdir $dir
    cp (root-cert) ($dir | path join "rootCA.pem")
    if ($dir | path join "rootCA-key.pem" | path exists) {
        error make --unspanned {msg: $"($dir) holds a CA key, refusing to use it"}
    }
    $dir
}

# Trusts the root CA on this host with mkcert.
def "main trust" []: nothing -> nothing {
    let caroot = (mkcert-caroot)
    with-env {CAROOT: $caroot} { ^mkcert -install }
}

# Removes the root CA from the trust stores mkcert manages.
def "main untrust" []: nothing -> nothing {
    let caroot = (mkcert-caroot)
    with-env {CAROOT: $caroot} { ^mkcert -uninstall }
}

# Shows the status.
def main []: nothing -> nothing { main status }
