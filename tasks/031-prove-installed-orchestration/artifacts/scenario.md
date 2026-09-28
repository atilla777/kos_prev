# Clean-Install Scenario

## Isolation

Build and install the CLI from the candidate checkout. Use separate temporary
directories for `KOS_DATA_HOME`, `GEM_HOME`, OpenCode configuration, and a
fixture Git repository. Install the managed OpenCode inventory with an absolute
`--config-home` path and invoke `/kos` from the fixture, not the KOS checkout.
The isolated configuration may use the operator's existing OpenCode provider
credentials, but the managed command and worker must inherit OpenCode's selected
model rather than naming a provider or model.

## Setup

Start a production Rails process with a fresh prepared and seeded database.
Through the packaged CLI, register the fixture repository and a one-step custom
workflow. The workflow tells a worker to perform the task description, report a
question when required information is absent, and report completion after the
requested observable file exists. Its outcomes are `completed`, `question`, and
`blocked`.

## First Session

Run `/kos` with a goal that requires one atomic plan containing three initially
independent tasks using the disclosed workflow key:

- create `alpha.txt` with fixed content;
- ask which color belongs in `color.txt`, then create it after a durable answer;
- wait before creating `recovered.txt`, allowing controlled interruption.

Observe at least two distinct `kos-worker` dispatches. Stop the OpenCode process
only after KOS shows the color task paused and the recovery task active, then
confirm the process has exited and retain the authoritative task projection.

## Fresh Session

Start a new `/kos` invocation without a project ID or plan key. State that the
prior process was stopped and answer the persisted color question. The
orchestrator must discover the repository's unfinished state, submit the answer,
explicitly take over the stopped active task with a new claim, dispatch workers,
and continue until every task is complete.

## Evidence

Retain the candidate and tool versions, installed manifest and inventory,
sanitized OpenCode event projections and raw-stream hashes, lifecycle snapshots,
fixture output hashes, and an evidence verifier. Do not retain API credentials,
provider credentials, complete model transcripts, or session identifiers.
