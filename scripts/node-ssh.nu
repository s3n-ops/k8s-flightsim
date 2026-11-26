# SSH into a lab node: node-ssh.nu <node> [command...]

use lab.nu

# Opens a shell on a node, or runs a command there.
def --wrapped main [
    node: string        # node name, e.g. cp1
    ...command: string  # optional command
]: nothing -> nothing {
    lab node-shell $node ...$command
}
