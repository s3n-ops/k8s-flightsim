# Agent Instructions

**Verbosity:** concise
**Chattiness:** low

## Language Policy

**Always** write code, code comments, commit messages and command output in
English. Communicate with the user in their preferred language, but **never**
write code or comments in the user's language. If the user's language
distinguishes between formal and informal pronouns, always use the informal
form.

All files in this repository are in English, including runbooks and
scenario texts, because it is published.

## Language Usage

Role model: News language.

- Information first.
- Short sentences, strong verbs.
- Be transparent, accountable, reliable and authentic.
- State facts in the indicative mood and uncertainties in the subjunctive mood.
  - *Correct (Fact):* "The node `w2` is Ready again."
  - *Correct (Uncertainty):* "This could cause a split brain if..."
  - *Incorrect:* "I think I have successfully fixed the node." (Do not guess about facts).
- **Avoid all-caps emphasis:** Do not use capitalization to emphasize rules, conditions, or importance (e.g., instead of "ALWAYS", use "**always**"). Use Markdown formatting for emphasis instead.
- **No dashes for clauses:** Do not use em-dashes (—) or en-dashes (–) to connect clauses or thoughts. Use commas, colons, or parentheses instead, or write shorter sentences.

## Admitting Mistakes

Admit mistakes immediately and without sugarcoating.
Do not call a mistake "confusion".

## Project

A local Kubernetes lab for operations and disaster recovery practice: Terraform
creates libvirt VMs, Ansible installs a kubeadm cluster with three control
plane nodes and three workers, `just` is the entry point.

- `just check` must pass before every commit. It runs Terraform format and
  validation, TFLint when installed, ansible-lint (profile production), a
  parse check of all Nushell files and nu-lint when installed.
- Runbooks follow `docs/runbooks/_template.md` (Symptom, Diagnosis, Cause,
  Fix, Verify, Prevention).
- Scenarios follow `scenarios/README.md` (types, layout, front matter).
  Each scenario links to a runbook.
- Host-specific values (paths, mount points) belong in
  `~/.config/k8s-flightsim/host.tfvars`, credentials and the kubeconfig in
  `~/.local/share/k8s-flightsim/`. Never in the working tree.

## Safety

The lab runs on the user's workstation. Ask before every command that
destroys or replaces state:

- `just down`, `just rebuild`, `just reset`, `just snapshot-delete`,
  `terraform destroy`, `terraform apply` that replaces resources
- `just scenario <id>`, because it breaks the cluster on purpose
- `virsh destroy`, `virsh undefine`, deleting volumes or pools

Read-only commands (`just status`, `just verify`, `kubectl get`,
`terraform plan`, `virsh list`) need no confirmation.

## Understand Before Improving

- **Blast radius:** If a change touches more than 3 files or changes the
  architecture (node layout, network, storage, backup path, repository
  layout), present a brief plan and wait for approval before modifying files.
- **Dependencies:** Do not introduce new tools, Helm charts, operators,
  Ansible collections or Terraform providers without explicit permission.
  Solve problems with the existing stack. Suggest a new dependency only if
  its value is exceptionally high.
- **Existing patterns first:** Extend what exists instead of adding new
  layers. Build only what is requested now (YAGNI), but make it fit the
  existing structure.
- **Pin versions** of everything that is downloaded (images, charts,
  providers, actions, remote manifests). Pick versions that are at least two
  weeks old.

## Nushell

Scripts on the workstation are Nushell, and so is the shell of the
`justfile`. Bash stays where commands run on the nodes: Ansible `shell`
tasks, commands sent over SSH, and the commands in the runbooks. The nodes
have no Nushell.

- Shared helpers live in `scripts/lab.nu`. Import it with
  `use ../../scripts/lab.nu` (paths resolve relative to the file).
- `lab node-run` fails on a non-zero exit, `lab node-try` returns the
  `complete` record. Use `node-try` where a failure is an expected result.
- Verify scripts collect `lab check <ok> --success ... --failure ...`
  results and end with `lab finish ...$results`.
- In a pipeline only the last external command's exit code counts. Capture
  the output of an earlier external command in a variable first.
- `^cmd | ignore` swallows the failure of an external command. Use
  `lab exec-checked` (or `lab virsh`, `lab node-run`), which fail with the
  command's stderr, or check `complete` yourself.
- Use `where`, not the deprecated `filter`.
- String interpolation: `$"Hello ($name)"`. Escape literal parentheses as
  `\(` and `\)`. Never write `$("...")`.
- Quote string arguments and values (`"cp1"`), use bare words for record
  keys (`{name: "cp1"}`).
- Multi-line commands: opening `(` on the line of `let`, one pipe or one
  flag per line, closing `)` on its own line, 4 spaces indentation.
- Give every `def` an output type and every `main` subcommand a doc comment
  and parameter comments, they show up in `--help`.

## Code Comments

Section headings in code are plain comments, not banners:

```
# Storage pool
```

Not `# ==== Storage pool ====` or `# ── Storage pool ──────`.

## Naming Conventions

Variables for paths, in Terraform, Ansible and shell alike:

- `dir`: relative directory (`output_dir = "output"`)
- `path`: absolute path, file or directory (`pool_path`)
- `file`: relative file (`config_file = "config.toml"`)
- `file_path`: absolute file path (`ssh_public_key_path` is the existing
  exception, kept for compatibility)

## Git Commits

Commit under the user's own credentials. Commit messages describe the
change, not the tools used to make it: no `Co-Authored-By` trailer, no
"Generated with" line, no tool names.

Before staging, check the diff for secrets and host-specific paths. If you
find one, name what and where, never the value, and stop.

The message:

- **Sentence case.** First letter capitalized, standard English
  capitalization, no trailing period.
- **Imperative mood.** "Add etcd quorum loss scenario", not "Adds" or "Added".
- **No type or topic prefix.** No `feat:`, `fix:`, `refactor:`, and no
  colon-separated prefix of any kind. Plain sentences only.
- **No emojis and no colons.**
- **Plain language.** Clear, specific wording without filler or
  generated-sounding phrases.
- **Short.** One line preferred, at most three, each at most 72 characters.
  Add lines only when the subject cannot carry the change: the subject line,
  a blank line, then one or two short lines of plain text. No bullet points.

Commit what the working tree holds. If it carries several unrelated changes,
say so and propose separate commits rather than inventing one message that
covers everything.

Branching, pull requests and publishing follow `GITHUB_RELEASE_POLICY.md` in
the repository root. Read it before the first commit of a session. It covers
the workflow only and never overrides the rules on secrets. **Never** push.

## Secrets

Credentials, tokens, keys, passwords, connection strings, kubeconfigs,
personal data: never printed, not in a response, log, commit message, error,
or comment. Refer to them by name or path.

Do not read `.env` files, keyrings, SSH private keys, kubeconfigs, or cloud
config unless that is exactly what was asked. Do not write a secret outside a
designated secret store, never into version control, never into an outward
call such as an API request, web search, or subagent prompt. Check the diff
before staging.

This project keeps **no secrets in git, not even encrypted ones** (no SOPS).
Kubernetes Secrets are created in the cluster at runtime and referenced by
name.

Found one incidentally: say what and where, never the value. Ambiguous case:
treat it as a secret.
