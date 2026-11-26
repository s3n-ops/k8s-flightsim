# Static checks for all Nushell scripts: parse errors via `nu --ide-check`,
# lint rules via nu-lint when it is installed.

use lab.nu

def nu-files []: nothing -> list<string> {
    cd $lab.LAB_ROOT
    glob "**/*.nu" --exclude ["**/.terraform/**"] | sort
}

def parse-errors [file_path: string]: nothing -> list<string> {
    ^nu --ide-check 100 $file_path
    | lines
    | each {|line| $line | from json }
    | where type == "diagnostic"
    | where severity == "Error"
    | each {|diagnostic| $"($file_path): ($diagnostic.message)" }
}

# Checks all Nushell files of the lab.
def main []: nothing -> nothing {
    let files = (nu-files)
    let errors = ($files | each {|file_path| parse-errors $file_path } | flatten)
    if ($errors | is-not-empty) {
        for error in $errors { lab fail $error }
        exit 1
    }
    lab pass $"($files | length) Nushell files parse"

    if (which nu-lint | is-empty) {
        lab info "nu-lint not installed, lint skipped"
        return
    }
    ^nu-lint --config ($lab.LAB_ROOT | path join "nu-lint.toml") --format compact ...$files
}
