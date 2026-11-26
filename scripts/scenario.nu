# Scenario runner ("flight simulator").
#
#   scenario.nu list
#   scenario.nu start <id>      inject the fault, show the task
#   scenario.nu verify <id>     check whether the cluster is healthy again
#   scenario.nu hint <id>
#   scenario.nu solution <id>   print the matching runbook
#
# A scenario is a directory scenarios/<id>/ with:
#   README.md  task; front matter with title, type, level, runbook
#   break.nu   injects the fault (optional for pure drills)
#   verify.nu  exits 0 when the task is solved
#   hint.md    optional hint

use lab.nu

const SCENARIOS_DIR = "scenarios"

def scenarios-path []: nothing -> string { $lab.LAB_ROOT | path join $SCENARIOS_DIR }

def resolve [id: string]: nothing -> string {
    let matches = (
        ls (scenarios-path)
        | where type == "dir"
        | where {|entry| ($entry.name | path basename) starts-with $id }
        | sort-by name
    )
    if ($matches | is-empty) {
        error make {
            msg: $"unknown scenario: ($id)"
            label: {text: "no scenario starts with this", span: (metadata $id).span}
        }
    }
    $matches | first | get name
}

def readme-lines [scenario_path: string]: nothing -> list<string> {
    open --raw ($scenario_path | path join "README.md") | lines
}

# Index of the closing "---" of the front matter.
def front-matter-end []: list<string> -> int {
    enumerate | where item == "---" | get -o 1.index | default 0
}

def front-matter [scenario_path: string]: nothing -> record {
    let lines = (readme-lines $scenario_path)
    $lines
    | slice 1..(($lines | front-matter-end) - 1)
    | parse "{key}: {value}"
    | reduce --fold {} {|row, fields| $fields | insert $row.key $row.value }
}

def body [scenario_path: string]: nothing -> string {
    let lines = (readme-lines $scenario_path)
    $lines | skip (($lines | front-matter-end) + 1) | str join "\n"
}

# Lists all scenarios.
def main []: nothing -> nothing { main list }

# Lists all scenarios.
def "main list" []: nothing -> nothing {
    ls (scenarios-path)
    | where type == "dir"
    | sort-by name
    | each {|entry|
        let fields = (front-matter $entry.name)
        {
            id: ($entry.name | path basename)
            type: $fields.type
            level: $fields.level
            title: $fields.title
        }
    }
    | print
}

# Injects the fault of a scenario and shows the task.
def "main start" [
    id: string  # scenario id or its prefix, e.g. 01
]: nothing -> nothing {
    let scenario_path = (resolve $id)
    let name = ($scenario_path | path basename)
    lab info $"scenario ($name): (front-matter $scenario_path | get title)"
    let break_file_path = ($scenario_path | path join "break.nu")
    if ($break_file_path | path exists) {
        lab info "injecting fault"
        ^nu $break_file_path
    }
    print ""
    print (body $scenario_path)
    print ""
    lab info $"check your work: just verify ($name)"
}

# Checks whether a scenario is solved.
def "main verify" [
    id: string  # scenario id or its prefix
]: nothing -> nothing {
    let scenario_path = (resolve $id)
    let name = ($scenario_path | path basename)
    try {
        ^nu ($scenario_path | path join "verify.nu")
        lab pass $"scenario ($name) solved"
    } catch {
        lab fail $"scenario ($name) not solved yet"
        exit 1
    }
}

# Shows the hint of a scenario.
def "main hint" [
    id: string  # scenario id or its prefix
]: nothing -> nothing {
    let hint_file_path = (resolve $id | path join "hint.md")
    if ($hint_file_path | path exists) {
        print (open --raw $hint_file_path)
    } else {
        lab info "no hint for this scenario"
    }
}

# Shows the runbook with the solution of a scenario.
def "main solution" [
    id: string  # scenario id or its prefix
]: nothing -> nothing {
    let runbook_file = (front-matter (resolve $id) | get runbook)
    print (open --raw ($lab.LAB_ROOT | path join $runbook_file))
}
