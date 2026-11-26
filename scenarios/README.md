# Scenarios

A scenario puts the cluster into a defined fault state and states a task.
Whoever runs it finds the cause, fixes it and checks the result with
`just verify`. Every scenario links to a runbook in
[`docs/runbooks/`](../docs/runbooks/README.md) that describes the solution.

## Types and levels

| Type | Meaning |
|---|---|
| `incident` | Something breaks, the cluster must be repaired. |
| `disaster` | Large parts of the cluster are lost, recovery is the task. |
| `drill` | No fault. A routine operation is practised, such as an upgrade or a backup. |

Levels are `easy`, `medium` and `hard`.

## Workflow

```bash
just scenarios          # list all scenarios
just scenario 01        # inject the fault and show the task
just hint 01            # show the hint
just verify 01          # check whether the task is solved
just solution 01        # show the runbook
just reset              # back to the snapshot "base"
```

An ID can be shortened to any unique prefix, such as `01`.

## Layout

Each scenario is a directory `scenarios/NN-name/`:

| File | Required | Content |
|---|---|---|
| `README.md` | yes | Front matter and the task, shown by `just scenario` |
| `verify.nu` | yes | Exits with 0 when the task is solved |
| `break.nu` | no | Injects the fault. Drills have none. |
| `hint.md` | no | A hint that points in the right direction without giving away the fix |

`README.md` starts with this front matter:

```yaml
---
title: Worker reports NotReady
type: incident
level: easy
runbook: docs/runbooks/node-notready-kubelet.md
---
```

The body states what counts as solved in a section `## Task`. Incidents
and disasters add a section `## Situation` before it, with what an
operator would notice.

## Adding a scenario

1. Copy an existing scenario of the same type and pick the next free
   number.
2. Write `break.nu` and `verify.nu` with the helpers from
   [`scripts/lab.nu`](../scripts/lab.nu). `verify.nu` collects
   `lab check` results and ends with `lab finish`.
3. Write the runbook from
   [`docs/runbooks/_template.md`](../docs/runbooks/_template.md) and link
   it in the front matter.
4. Run the scenario from the snapshot it expects, solve it once, and run
   `just check`.
