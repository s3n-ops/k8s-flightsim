# k8s-flightsim lab: `just` lists all recipes.

set shell := ["nu", "-c"]

# Host settings (XDG config) and credentials (XDG data) live outside the
# repository: nothing host-specific or secret is ever in the working tree.
config_dir := env("FLIGHTSIM_CONFIG_DIR", env("XDG_CONFIG_HOME", home_directory() / ".config") / "k8s-flightsim")
data_dir := env("FLIGHTSIM_DATA_DIR", env("XDG_DATA_HOME", home_directory() / ".local" / "share") / "k8s-flightsim")
host_vars := config_dir / "host.tfvars"

export FLIGHTSIM_DATA_DIR := data_dir
export KUBECONFIG := data_dir / "kubeconfig"

# Local checkout of the GitOps repository
gitops := justfile_directory() / ".." / "k8s-flightsim-gitops"

default:
    @just --list --unsorted

# Lifecycle

# Create the config and data directories. An existing config is never touched.
init:
    #!/usr/bin/env nu
    mkdir '{{ config_dir }}' '{{ data_dir }}'
    ^chmod 700 '{{ data_dir }}'
    for pair in [[skel target]; [conf/host.skel.tfvars host.tfvars] [conf/pki.skel.toml pki.toml] [conf/backup.skel.toml backup.toml]] {
        let target = ('{{ config_dir }}' | path join $pair.target)
        if ($target | path exists) {
            print $"config exists, not touched: ($target)"
        } else {
            cp $pair.skel $target
            print $"created ($target) from ($pair.skel), please review it"
        }
    }

# Create network, volumes and VMs (Terraform)
infra *args: _host-vars
    cd terraform; terraform init -input=false | ignore; terraform apply -var-file='{{ host_vars }}' {{ args }}

# Install Kubernetes on the VMs (Ansible)
bootstrap:
    cd ansible; ansible-playbook site.yml

# Full build, then a "base" snapshot of the bare cluster
up: infra bootstrap (snapshot "base")

# Destroy everything, snapshots included
down: _host-vars
    nu scripts/backup.nu target-stop
    nu scripts/snapshot.nu purge
    cd terraform; terraform destroy -var-file='{{ host_vars }}'

# down + up
rebuild: down up

# Shut VMs, backup target and network down, keep disks and snapshots
stop:
    nu scripts/power.nu stop

# Start the network, backup target and all VMs, wait for the API server
start:
    nu scripts/power.nu start

# PKI

# Lab CA: init, rotate-intermediate, status (default), trust, untrust
pki cmd="status":
    #!/usr/bin/env bash
    # age turns off terminal echo while it asks for a passphrase. Restore the
    # terminal even when the run is interrupted with Ctrl+C.
    saved_tty=$(stty -g 2>/dev/null || true)
    trap '[ -n "$saved_tty" ] && stty "$saved_tty" 2>/dev/null' EXIT INT TERM
    nu scripts/pki.nu {{ cmd }}

# GitOps

# Create the Secrets the GitOps repo references (values in ~/.local/share/k8s-flightsim)
secrets:
    nu scripts/secrets.nu

# Install Argo CD, its projects and the root application from the GitOps repo
argocd:
    kubectl apply --server-side --force-conflicts -k '{{ gitops }}/bootstrap/argocd'
    kubectl -n argocd rollout status deployment argocd-server --timeout=300s
    kubectl apply -f '{{ gitops }}/bootstrap/root.yaml'

# Initial Argo CD admin password
argocd-password:
    @kubectl -n argocd get secret argocd-initial-admin-secret -o json | from json | get data.password | decode base64 | decode

# Miniflux admin password (user admin), created by just secrets
miniflux-password:
    @open --raw '{{ data_dir }}/secrets/miniflux-admin-password' | str trim

# URL of the Argo CD UI (through the lab gateway)
argocd-ui:
    @print "https://argocd.k8s-flightsim.internal"

# Snapshots

# Snapshot all nodes (shuts the cluster down briefly)
snapshot name="base":
    nu scripts/snapshot.nu create {{ name }}

# Roll all nodes back to a snapshot
reset name="base":
    nu scripts/snapshot.nu revert {{ name }}

# List snapshots
snapshots:
    nu scripts/snapshot.nu list

# Delete a snapshot
snapshot-delete name:
    nu scripts/snapshot.nu delete {{ name }}

# Backups

# Back up the cluster with Velero, asks first
backup name="":
    nu scripts/backup.nu create {{ name }}

# List Velero backups and the space they use
backups:
    nu scripts/backup.nu list

# Delete a Velero backup, asks first
backup-delete name:
    nu scripts/backup.nu delete {{ name }}

# Delete all but the newest completed backups, asks first
backup-prune keep="1":
    nu scripts/backup.nu prune {{ keep }}

# Restore a Velero backup, asks first
restore name:
    nu scripts/backup.nu restore {{ name }}

# Scenarios

# List scenarios
scenarios:
    nu scripts/scenario.nu list

# Inject a fault and show the task (just scenario 01)
scenario id:
    nu scripts/scenario.nu start {{ id }}

# Check whether a scenario is solved
verify id:
    nu scripts/scenario.nu verify {{ id }}

# Show a hint
hint id:
    nu scripts/scenario.nu hint {{ id }}

# Show the runbook with the solution
solution id:
    nu scripts/scenario.nu solution {{ id }}

# Operations

# VMs, network, and nodes and system pods if the cluster runs
status:
    nu scripts/power.nu status

# SSH into a node (just ssh cp1)
ssh node *cmd:
    nu scripts/node-ssh.nu {{ node }} {{ cmd }}

# Disk usage of the lab pool
usage:
    virsh -c qemu:///system pool-info k8s-flightsim | lines | where {|line| $line =~ 'Capacity|Allocation|Available' } | str join "\n"
    virsh -c qemu:///system vol-list k8s-flightsim --details | lines | enumerate | where {|row| $row.index < 2 or $row.item =~ 'qcow2|raw' } | get item | str join "\n"

# Path of the kubeconfig (bash: export KUBECONFIG=$(just kubeconfig))
kubeconfig:
    @print '{{ KUBECONFIG }}'

# Terraform falls back to defaults without host settings and would move the
# pool. Refuse instead.
[private]
_host-vars:
    @if not ('{{ host_vars }}' | path exists) { error make --unspanned {msg: "missing {{ host_vars }}, run just init"} }

# Reference solution of the upgrade drill (just upgrade 1.37)
upgrade to="":
    cd ansible; ansible-playbook upgrade.yml {{ if to == "" { "" } else { "-e kubernetes_upgrade_version=" + to } }}

# Lint Terraform (tflint when installed), Ansible and Nushell scripts
check:
    cd terraform; terraform fmt -check -recursive; terraform init -input=false -backend=false | ignore; terraform validate
    if (which tflint | is-not-empty) { ^tflint --chdir=terraform --format=compact } else if ($env.CI? == "true") { error make --unspanned {msg: "tflint is required in CI"} } else { print "tflint not installed, skipped" }
    cd ansible; ansible-lint site.yml upgrade.yml
    nu scripts/check.nu
