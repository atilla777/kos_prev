# Corrected Live Report Evidence

Date: 2026-09-27
OpenCode: 1.18.26
Installed source identity:
`sha256:a6a72687a76b9acba24c3bc585acdb00c4a20c319e8cc51744975fc563545319`

The focused run reused task 025's isolated production database, data home,
packaged CLI, OpenCode configuration, fixture repository, SSH transport, and
bare remote. The changed integration assets were reinstalled from the candidate
checkout before execution. No credential or raw model transcript is retained.

## Custom Sequence

Custom task 6 used the existing three-step workflow. After its verified
worktree was provisioned, one scheduler invocation completed:

| Step | Profile | Submitted owner | Claim version | Result |
| --- | --- | --- | --- | --- |
| `main_probe` | fixed advanced main | `kos-session-6a0...` | 1 | `ready` accepted |
| `standard_probe` | standard Terra subagent | `kos-session-6a0...` | 2 | `inspected` accepted |
| `advanced_probe` | advanced Sol subagent | `kos-session-6a0...` | 3 | `finished` accepted |

The task completed at claim version 4 with released ownership. In particular,
the standard subagent had predecessor evidence accepted at version 1 but used
the current task version 2 and the scheduler's active owner. It did not run
`session-id` or submit a stale owner.

## Built-In Sequence

Development task 7 first paused at plan for one product decision, reporting
with the current owner and version 1. The same command session supplied the
answer, resumed to version 3, and completed this accepted sequence:

| Step | Profile | Submitted owner | Claim version | Result |
| --- | --- | --- | --- | --- |
| `plan` | advanced Sol subagent | `kos-session-fae...` | 3 | `planned` accepted |
| `implement` | standard Terra subagent | `kos-session-fae...` | 4 | `implemented` accepted |
| `document` | standard Terra subagent | `kos-session-fae...` | 5 | `documented` accepted |
| `review` | advanced Sol subagent | `kos-session-fae...` | 6 | `approved` accepted |
| `publish` | standard Terra subagent | `kos-session-fae...` | 7 | `published` accepted |

The task completed at claim version 8 with released ownership and the exact
reviewed commit observed on the isolated remote. Every standard report used the
same authoritative owner while advancing through current task versions; none
used an accepted predecessor version and no report was rejected as stale.

The initial custom invocation stopped before the sequence because its worktree
had not yet been provisioned, and the development plan paused for an explicit
product decision. Neither event was a stale report or an automatic redispatch.
