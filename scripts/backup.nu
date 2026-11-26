# Velero backups of the lab cluster.
#
#   backup.nu create [name]   back up the cluster, asks first
#   backup.nu list            list backups and the space they use
#   backup.nu restore <name>  restore a backup, asks first
#   backup.nu delete <name>   delete a backup, asks first
#   backup.nu prune [keep]    keep the newest completed backups, asks first
#   backup.nu target-stop     stop the backup target (used by just down)
#
# The backup target is rclone on the host, serving backup_path as S3 on
# the lab bridge. It runs while the lab runs, see lab start-cluster.

use lab.nu

const NAMESPACE = "velero"
const FINAL_PHASES = ["Completed" "PartiallyFailed" "Failed" "FailedValidation"]

# Phase of a Velero object, empty while Velero has not picked it up.
def phase [kind: string, name: string]: nothing -> string {
    let result = (
        ^kubectl -n $NAMESPACE get $kind $name -o "jsonpath={.status.phase}" | complete
    )
    if $result.exit_code != 0 { "" } else { $result.stdout | str trim }
}

# Waits until a backup or restore has finished. Gives up after 30 minutes.
def wait-final [kind: string, name: string]: nothing -> string {
    mut last = ""
    mut final = ""
    mut tries = 0
    while ($final | is-empty) and $tries < 360 {
        let current = (phase $kind $name)
        if $current != $last and ($current | is-not-empty) {
            lab info $"($kind) ($name): ($current)"
            $last = $current
        }
        if $current in $FINAL_PHASES {
            $final = $current
        } else {
            sleep 5sec
            $tries += 1
        }
    }
    if ($final | is-empty) {
        error make --unspanned {msg: $"($kind) ($name) did not finish within 30 minutes"}
    }
    $final
}

# Fails unless Velero can reach the backup storage.
def require-storage []: nothing -> nothing {
    lab wait-api
    if (lab s3-state) != "active" {
        error make --unspanned {msg: "backup target is not running: set backup_path in backup.toml, run just secrets, then just start"}
    }
    let result = (
        ^kubectl -n $NAMESPACE get backupstoragelocation default -o "jsonpath={.status.phase}"
        | complete
    )
    if $result.exit_code != 0 {
        error make --unspanned {msg: "Velero is not installed (BackupStorageLocation default missing)"}
    }
    if ($result.stdout | str trim) != "Available" {
        error make --unspanned {msg: "Velero cannot reach the backup target yet, try again in a minute"}
    }
}

# Applies a Velero object given as a record.
def apply-object [object: record]: nothing -> nothing {
    let manifest = ($object | to yaml)
    let result = ($manifest | ^kubectl apply -f - | complete)
    if $result.exit_code != 0 {
        error make --unspanned {msg: $"kubectl apply failed: ($result.stderr | str trim)"}
    }
}

# Prints the result and fails unless the phase is Completed.
def report [kind: string, name: string, final: string]: nothing -> nothing {
    if $final == "Completed" {
        lab pass $"($kind) ($name) completed"
    } else {
        lab fail $"($kind) ($name) ended with phase ($final)"
        let details = (
            ^kubectl -n $NAMESPACE get $kind $name -o "jsonpath={.status}" | complete
        )
        if $details.exit_code == 0 { print ($details.stdout | from json | to yaml) }
        error make --unspanned {msg: $"($kind) ($name): ($final)"}
    }
}

# Stops the backup target. just down calls it before the network goes away.
def "main target-stop" []: nothing -> nothing { lab s3-stop }

# Backs up all namespaces after a confirmation.
def "main create" [
    name: string = ""  # backup name, default manual-<timestamp>
]: nothing -> nothing {
    require-storage
    let backup_name = if ($name | is-empty) {
        $"manual-(date now | format date '%Y%m%d-%H%M%S')"
    } else { $name }
    print $"Backup ($backup_name): all namespaces, volumes with Kopia."
    print "CloudNativePG pods and volumes are excluded. Kept for 30 days."
    if not (lab confirm "Create the backup?") {
        lab info "cancelled"
        return
    }
    apply-object {
        apiVersion: "velero.io/v1"
        kind: "Backup"
        metadata: {name: $backup_name, namespace: $NAMESPACE}
        spec: {
            includedNamespaces: ["*"]
            defaultVolumesToFsBackup: true
            storageLocation: "default"
            ttl: "720h0m0s"
        }
    }
    report "backup" $backup_name (wait-final "backup" $backup_name)
}

# All backups, oldest first.
def backups []: nothing -> table {
    let result = (^kubectl -n $NAMESPACE get backups.velero.io -o json | complete)
    if $result.exit_code != 0 {
        error make --unspanned {msg: $"kubectl failed: ($result.stderr | str trim)"}
    }
    $result.stdout
    | from json
    | get items
    | each {|item|
        {
            name: $item.metadata.name
            phase: ($item.status?.phase? | default "New")
            created: ($item.metadata.creationTimestamp | into datetime)
            expires: ($item.status?.expiration? | default "")
            errors: ($item.status?.errors? | default 0)
            warnings: ($item.status?.warnings? | default 0)
        }
    }
    | sort-by created
}

# Lists all backups and the space the backup directory uses on the host.
def "main list" []: nothing -> nothing {
    lab wait-api
    print (backups)
    let path = (lab backup-path)
    if ($path | is-empty) or not ($path | path exists) { return }
    let usage = (
        ["backups" "kopia"]
        | each {|dir| $path | path join "velero" $dir }
        | where {|dir| $dir | path exists }
        | each {|dir| {directory: $dir, size: (du $dir | get 0.physical)} }
    )
    print $usage
    print "Kopia stores each block once, so backups share space. Deleted backups free space only after the next repository maintenance."
}

# Asks Velero to delete backups. Deleting the Backup object alone would not
# remove the data, and Velero would sync the object back from storage.
def delete-backups [names: list<string>]: nothing -> nothing {
    for name in $names {
        apply-object {
            apiVersion: "velero.io/v1"
            kind: "DeleteBackupRequest"
            metadata: {name: $"($name)-delete-(random uuid | str substring 0..7)", namespace: $NAMESPACE}
            spec: {backupName: $name}
        }
        lab pass $"deletion of ($name) requested"
    }
}

# Deletes one backup after a confirmation.
def "main delete" [
    name: string  # backup name, see backup.nu list
]: nothing -> nothing {
    require-storage
    if ($name not-in (backups | get name)) {
        error make --unspanned {msg: $"no backup named ($name), see just backups"}
    }
    if not (lab confirm $"Delete backup ($name) and its data?") {
        lab info "cancelled"
        return
    }
    delete-backups [$name]
}

# Keeps the newest completed backups and deletes all others.
def "main prune" [
    keep: int = 1  # number of completed backups to keep
]: nothing -> nothing {
    require-storage
    if $keep < 1 {
        error make --unspanned {msg: "keep at least one backup"}
    }
    let all = (backups)
    let kept = ($all | where phase == "Completed" | last $keep | get name)
    let doomed = ($all | where {|backup| $backup.name not-in $kept })
    if ($doomed | is-empty) {
        lab info "nothing to delete"
        return
    }
    print "Keep:"
    print ($kept | each {|name| $"  ($name)" } | str join "\n")
    print "Delete:"
    print ($doomed | each {|backup| $"  ($backup.name) \(($backup.phase)\)" } | str join "\n")
    if not (lab confirm $"Delete ($doomed | length) backups and their data?") {
        lab info "cancelled"
        return
    }
    delete-backups ($doomed | get name)
}

# Restores a backup after a confirmation.
def "main restore" [
    name: string  # backup name, see backup.nu list
]: nothing -> nothing {
    require-storage
    let backup_phase = (phase "backup" $name)
    if ($backup_phase | is-empty) {
        error make --unspanned {msg: $"no backup named ($name), see just backups"}
    }
    if $backup_phase not-in ["Completed" "PartiallyFailed"] {
        error make --unspanned {msg: $"backup ($name) has phase ($backup_phase), nothing to restore"}
    }
    let restore_name = $"($name)-(date now | format date '%Y%m%d-%H%M%S')"
    print $"Restore ($restore_name) from backup ($name)."
    print "Missing resources are recreated, existing ones are left as they are."
    print "To bring back a deleted namespace, delete it completely first."
    if not (lab confirm "Start the restore?") {
        lab info "cancelled"
        return
    }
    apply-object {
        apiVersion: "velero.io/v1"
        kind: "Restore"
        metadata: {name: $restore_name, namespace: $NAMESPACE}
        spec: {backupName: $name}
    }
    report "restore" $restore_name (wait-final "restore" $restore_name)
}

def main []: nothing -> nothing { main list }
