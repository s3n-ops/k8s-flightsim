# Shared helpers for the lab scripts. Import with `use`, do not run.
#
# Settings can be overridden with environment variables:
# LIBVIRT_URI, PREFIX, SSH_USER, KUBECONFIG, FLIGHTSIM_DATA_DIR.

export const LAB_ROOT = (path self | path dirname | path dirname)
export const INVENTORY_FILE_PATH = ($LAB_ROOT | path join "ansible" "inventory.yml")

# Lab VMs get rebuilt often, their host keys change.
const SSH_OPTIONS = [
    "-o" "StrictHostKeyChecking=no"
    "-o" "UserKnownHostsFile=/dev/null"
    "-o" "LogLevel=ERROR"
]

# Host settings live outside the repository, in the XDG config directory.
export def config-dir []: nothing -> string {
    $env.FLIGHTSIM_CONFIG_DIR? | default (
        $env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config") | path join "k8s-flightsim"
    )
}

# Credentials live outside the repository, in the XDG data directory.
export def data-dir []: nothing -> string {
    $env.FLIGHTSIM_DATA_DIR? | default (
        $env.XDG_DATA_HOME? | default ($env.HOME | path join ".local" "share") | path join "k8s-flightsim"
    )
}

export-env {
    $env.KUBECONFIG = ($env.KUBECONFIG? | default (data-dir | path join "kubeconfig"))
}

# libvirt connection URI.
export def libvirt-uri []: nothing -> string { $env.LIBVIRT_URI? | default "qemu:///system" }
# Name prefix of all libvirt objects.
export def prefix []: nothing -> string { $env.PREFIX? | default "k8s-flightsim" }
# Login user on the nodes.
export def ssh-user []: nothing -> string { $env.SSH_USER? | default "ubuntu" }

#
# Output
#

# Prints a progress message.
export def info [message: string]: nothing -> nothing { print $"(ansi blue_bold)==>(ansi reset) ($message)" }
# Prints a passed check.
export def pass [message: string]: nothing -> nothing { print $"(ansi green_bold)[OK](ansi reset) ($message)" }
# Prints a failed check.
export def fail [message: string]: nothing -> nothing { print $"(ansi red_bold)[FAIL](ansi reset) ($message)" }

# Prints the result of one check and returns it.
export def check [
    ok: bool                # result of the check
    --success: string = ""  # message when ok
    --failure: string = ""  # message when not ok
]: nothing -> bool {
    if $ok { pass $success } else { fail $failure }
    $ok
}

# Asks a yes/no question on the terminal. Only "y" or "yes" confirms.
export def confirm [question: string]: nothing -> bool {
    (input $"($question) [y/N] " | str trim) =~ '^(?i)y(es)?$'
}

# Fails unless every check passed, so the script exits non-zero.
export def finish [...results: bool]: nothing -> nothing {
    let failed = ($results | where {|result| not $result } | length)
    if $failed > 0 {
        error make --unspanned {msg: $"($failed) of ($results | length) checks failed"}
    }
}

#
# libvirt
#

# Runs an external command and returns its stdout. Fails with its stderr
# on a non-zero exit. Use it instead of `^cmd | ignore`: piping into ignore
# swallows the failure of an external command.
export def exec-checked [command: string, ...args: string]: nothing -> string {
    let result = (^$command ...$args | complete)
    if $result.exit_code != 0 {
        error make --unspanned {
            msg: $"`([$command ...$args] | str join ' ')` failed: ($result.stderr | str trim)"
        }
    }
    $result.stdout
}

# virsh against the lab connection. Fails on a non-zero exit.
export def virsh [...args: string]: nothing -> string {
    exec-checked "virsh" "-c" (libvirt-uri) ...$args
}

# All lab domains, control plane first (cp* sorts before w*).
export def domains []: nothing -> list<string> {
    virsh "list" "--all" "--name"
    | lines
    | where {|domain| $domain starts-with $"(prefix)-" }
    | sort
}

# Control plane domains, sorted.
export def control-plane-domains []: nothing -> list<string> {
    domains | where {|domain| $domain starts-with $"(prefix)-cp" }
}

# Worker domains, sorted.
export def worker-domains []: nothing -> list<string> {
    domains | where {|domain| not ($domain starts-with $"(prefix)-cp") }
}

# State of a domain, e.g. "running" or "shut off".
export def domain-state [domain: string]: nothing -> string {
    virsh "domstate" $domain | str trim
}

# Node name of a domain: k8s-flightsim-cp1 -> cp1.
export def node-name [domain: string]: nothing -> string {
    $domain | str replace $"(prefix)-" ""
}

# Waits until a domain is shut off. Forces power off after three minutes.
export def wait-shut-off [domain: string]: nothing -> nothing {
    for _ in 1..60 {
        if (domain-state $domain) == "shut off" { return }
        sleep 3sec
    }
    info $"($domain) did not shut down in time, forcing power off"
    virsh "destroy" $domain | ignore
}

# True when the lab network is defined and running.
export def network-active []: nothing -> bool {
    let result = (^virsh "-c" (libvirt-uri) "net-info" (prefix) | complete)
    $result.exit_code == 0 and ($result.stdout =~ '(?m)^Active:\s+yes')
}

# Shuts down the workers, then the control plane, waits for all and
# stops the lab network. Its definition stays.
export def stop-cluster []: nothing -> nothing {
    info "shutting down workers, then control plane"
    for domain in ((worker-domains) ++ (control-plane-domains)) {
        if (domain-state $domain) == "running" {
            virsh "shutdown" $domain | ignore
        }
    }
    for domain in (domains) { wait-shut-off $domain }
    s3-stop
    if (network-active) {
        info $"stopping network (prefix)"
        virsh "net-destroy" (prefix) | ignore
    }
}

# Starts the lab network, then the control plane, then the workers.
export def start-cluster []: nothing -> nothing {
    if not (network-active) {
        info $"starting network (prefix)"
        virsh "net-start" (prefix) | ignore
    }
    s3-start
    info "starting control plane, then workers"
    for domain in ((control-plane-domains) ++ (worker-domains)) {
        if (domain-state $domain) != "running" {
            virsh "start" $domain | ignore
        }
    }
}

#
# Backup target
#
# rclone serves the backup directory as S3 to the cluster. It runs as a
# transient systemd user unit while the lab runs: start-cluster starts it,
# stop-cluster stops it. No unit file is written, nothing survives a reboot.

export const S3_PORT = 9000
const S3_BUCKET = "velero"

# Name of the transient user unit.
export def s3-unit []: nothing -> string { $"(prefix)-s3" }

# Backup directory from backup.toml, empty when not configured.
export def backup-path []: nothing -> string {
    let config_file_path = (config-dir | path join "backup.toml")
    if not ($config_file_path | path exists) { return "" }
    let path = (open $config_file_path | get backup_path? | default "" | str trim)
    if ($path | is-empty) { "" } else { $path | path expand }
}

# Address of the host on the lab network, from the libvirt definition.
export def host-ip []: nothing -> string {
    virsh "net-dumpxml" (prefix)
    | parse --regex "<ip address='(?<address>[0-9.]+)'"
    | get address
    | first
}

# State of the backup target unit, e.g. "active" or "inactive".
export def s3-state []: nothing -> string {
    ^systemctl --user is-active (s3-unit) | complete | get stdout | str trim
}

# Starts the backup target unless it runs or is not configured.
export def s3-start []: nothing -> nothing {
    if (s3-state) == "active" { return }
    let path = (backup-path)
    let secrets_path = (data-dir | path join "secrets")
    let key_file_paths = (
        ["velero-s3-access-key" "velero-s3-secret-key"]
        | each {|name| $secrets_path | path join $name }
    )
    let rclone = (which rclone)
    if ($path | is-empty) or ($rclone | is-empty) or ($key_file_paths | any {|file_path| not ($file_path | path exists) }) {
        info "backup target not started: needs backup_path in backup.toml, rclone and just secrets"
        return
    }
    mkdir ($path | path join $S3_BUCKET)
    let access_key = (open --raw ($secrets_path | path join "velero-s3-access-key") | str trim)
    let secret_key = (open --raw ($secrets_path | path join "velero-s3-secret-key") | str trim)
    # The keys reach rclone through an environment file, not the process
    # list. rclone reads list flags from the environment as CSV, hence the
    # inner double quotes.
    let runtime_dir = ($env.XDG_RUNTIME_DIR? | default "/tmp")
    let env_file_path = ($runtime_dir | path join $"(s3-unit)-(random chars --length 8).env")
    "" | save $env_file_path
    ^chmod "600" $env_file_path
    $"RCLONE_AUTH_KEY='\"($access_key),($secret_key)\"'\n" | save --force $env_file_path
    let address = $"(host-ip):($S3_PORT)"
    let result = (
        ^systemd-run --user --collect --quiet
            $"--unit=(s3-unit)"
            $"--property=EnvironmentFile=($env_file_path)"
            ($rclone | first | get path) "serve" "s3" $path "--addr" $address
        | complete
    )
    # rclone has read the file once systemd started it.
    sleep 1sec
    rm --force $env_file_path
    if $result.exit_code != 0 {
        error make --unspanned {msg: $"backup target did not start: ($result.stderr | str trim)"}
    }
    info $"backup target ($path) served as S3 on http://($address)"
}

# Stops the backup target if it runs.
export def s3-stop []: nothing -> nothing {
    if (s3-state) in ["active" "activating" "failed"] {
        info "stopping backup target"
        ^systemctl --user stop (s3-unit) | complete | ignore
    }
}

#
# Nodes
#

# IP address of a node from the Ansible inventory.
export def node-ip [node: string]: nothing -> string {
    open $INVENTORY_FILE_PATH
    | get all.children
    | values
    | each {|group| $group.hosts }
    | reduce {|hosts, all_hosts| $all_hosts | merge $hosts }
    | get -o $node
    | get -o ansible_host
    | default { error make {msg: $"node ($node) not in ($INVENTORY_FILE_PATH)"} }
}

# Runs a command on a node and returns the complete record
# (stdout, stderr, exit_code). Never fails.
export def node-try [node: string, command: string]: nothing -> record {
    ^ssh ...$SSH_OPTIONS $"(ssh-user)@(node-ip $node)" $command | complete
}

# Runs a command on a node and returns its stdout. Fails on a non-zero exit.
export def node-run [node: string, command: string]: nothing -> string {
    let result = (node-try $node $command)
    if $result.exit_code != 0 {
        error make {
            msg: $"($node): `($command)` failed: ($result.stderr | str trim)"
            label: {text: "remote command failed", span: (metadata $command).span}
        }
    }
    $result.stdout
}

# Interactive SSH session, or a command with output on the terminal.
# The output type stays open: ssh writes straight to the terminal.
export def node-shell [node: string, ...command: string] {
    ^ssh ...$SSH_OPTIONS $"(ssh-user)@(node-ip $node)" ...$command
}

#
# Kubernetes
#

# "True", "False", "Unknown" or "missing".
export def node-ready [node: string]: nothing -> string {
    let result = (^kubectl get node $node -o json | complete)
    if $result.exit_code != 0 { return "missing" }
    $result.stdout
    | from json
    | get status.conditions
    | where type == "Ready"
    | get -o 0.status
    | default "Unknown"
}

# True when the API server answers on the VIP within three seconds.
export def api-ready []: nothing -> bool {
    (^kubectl get --raw /livez --request-timeout=3s | complete).exit_code == 0
}

# Waits until the API server answers on the VIP. Fails after five minutes.
export def wait-api []: nothing -> nothing {
    mut ready = false
    for _ in 1..60 {
        $ready = (api-ready)
        if $ready { break }
        sleep 5sec
    }
    if not $ready {
        error make --unspanned {msg: "API server not reachable after five minutes"}
    }
}
