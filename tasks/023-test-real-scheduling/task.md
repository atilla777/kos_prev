# Test Real Scheduling

## Goal

Replace prompt-text claims with deterministic execution evidence for scheduler
control flow, installed generic profiles, and end-to-end built-in task progress.

## Source Evidence

- Existing scheduler tests mostly search managed Markdown for required phrases.
- The acceptance matrix labels direct lifecycle tests as real scenarios even
  though they bypass OpenCode dispatch and scheduler looping.
- Current recovery, mode, tier, and terminal behavior therefore can regress
  while `bin/check` remains green.
- See task 018's `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Build a deterministic installed-command harness with a fake CLI and fake
  foreground child runner.
- Execute development, fix, brief, and the task-021 custom contract through
  actual scheduler control flow without live model credentials.
- Verify ID-only child prompts, main/subagent selection, standard/advanced tier,
  report ownership, bounded recovery, pause/resume, backward transitions, and
  terminal stop.
- Keep direct Rails lifecycle and Git fixture tests as lower-layer coverage.
- Rename or remap acceptance criteria so deterministic lifecycle tests are not
  described as live model E2E.

## Out Of Scope

- Replacing required live release acceptance.
- Simulating model quality or judging Markdown semantics.
- Introducing a production runtime broker.

## Acceptance Criteria

- The checked-in command and skill inventory is exercised as installed input to
  a deterministic scheduler harness.
- All supported task types reach their expected terminal state in the harness.
- Crash, unchanged context, lease expiry, pause/resume, and backward correction
  paths execute rather than being asserted by string matching.
- String tests remain only for static inventory or wording contracts that cannot
  be observed behaviorally.
- The acceptance matrix accurately distinguishes domain lifecycle, scheduler
  integration, Git fixtures, package smoke, and live-model evidence.
- `bin/check` passes.
