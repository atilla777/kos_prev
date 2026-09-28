# Clean-Install Acceptance Evidence

Date: 2026-09-28
Candidate source identity:
`sha256:2a849431b46131d1e684eff5cee4b62b9307a8630c335fe7a64a787eeba7f651`

## Isolation

The run used a fresh production database, packaged CLI installed under an
isolated gem home, an absolute isolated OpenCode configuration home, and a new
fixture Git repository. OpenCode ran from the fixture rather than the KOS
checkout. External skills and plugins were disabled. Existing provider
credentials were inherited, while the installed command and worker contained no
provider or model selection; OpenCode selected `openai/gpt-5.6-sol` for this
operator.

Because `opencode run` cannot answer interactive permission prompts, the
headless run supplied only `permission.doom_loop=allow` through
`OPENCODE_CONFIG_CONTENT`. The shipped installation did not add a permission
policy.

## Scenario

The first real `/kos` invocation discovered the project from its Git remote,
found no unfinished state, and stored plan `installed-orchestration-031` with
three blocker-free tasks using custom workflow `acceptance` revision 1. It
claimed all three tasks within 57 milliseconds. The main orchestrator issued no
fixture write command.

Separate workers began the tasks. The color worker reported the durable question
`Which color should color.txt contain?`; alpha and recovery still had active
claims when the orchestrator process was stopped. The retained interrupted
projection records the pause and hashes, rather than values, of the two claims.

A new `/kos` invocation received no project ID or plan key. It rediscovered the
project and unfinished state, bound answer `blue` to the paused step, explicitly
took over both stopped active tasks with different claims, and claimed the
answered color task. Three recorded `kos-worker` launches used only immutable
task/version/step envelopes and ran concurrently. KOS ended with all tasks
complete and no claims, pauses, or answers. The fixture contained the three
expected one-line files.

## Reproduced Regression

Before the final run, the installed orchestrator repeatedly guessed the plan
payload because `plan put --help` exposed the file option but not the required
JSON fields. That exhausted OpenCode's headless doom-loop permission. The final
candidate adds the exact task field names to CLI help, automated CLI coverage,
and matching first-run examples. The final run used that candidate and created
the plan on its first `plan put` attempt.

## Retained Evidence

- `provenance.json` records source and tool versions.
- `installed-inventory.txt` records the exact managed assets.
- `observations.json` contains sanitized lifecycle and worker-launch projections.
- `stream-hashes.json` binds the two unretained raw JSON event streams by hash,
  byte count, and line count.
- `verify_evidence.rb` checks the retained acceptance assertions.

No API token, provider credential, raw model transcript, claim value, OpenCode
session identifier, or temporary path is retained.
