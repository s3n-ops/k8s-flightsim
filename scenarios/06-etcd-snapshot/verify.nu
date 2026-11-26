use ../../scripts/lab.nu

const SNAPSHOT_FILE_PATH = "/var/backups/etcd/snapshot.db"

def main []: nothing -> nothing {
    let result = (lab node-try "cp1" $"sudo etcdutl snapshot status ($SNAPSHOT_FILE_PATH) -w json")
    let valid = ($result.exit_code == 0)
    let summary = if $valid {
        let status = ($result.stdout | from json)
        $"snapshot valid: revision ($status.revision), ($status.totalKey) keys"
    } else { "" }
    (
        lab finish
            (lab check $valid --success $summary --failure $"no valid snapshot at ($SNAPSHOT_FILE_PATH)")
    )
}
