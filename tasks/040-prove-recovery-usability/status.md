# Status

State: done
Updated: 2026-09-28

## Current

The clean installed run proved CLI discovery, planning-only stop, observable
runtime cancellation, exact release and stale-report rejection, fresh-session
status and takeover, and completion through independent review and publication.
The published fixture is
`https://github.com/atilla777/kos-recovery-acceptance-040`; its observed remote
`main` is retained in a self-contained bundle.

## Decisions

- Keep live execution as retained acceptance evidence rather than a routine CI
  dependency.
- Treat source inspection, guessed workflow keys, fallback workflow creation,
  duplicate plans, and implicit execution as acceptance failures.
- Retain sanitized tool events plus a complete line manifest so command ordering
  and event-selection completeness are reviewable without publishing raw claims,
  sessions, credentials, or full model transcripts.
- No stable mechanical regression was found, so no product code or automated
  regression test was required.

## Checks

- `bin/check`
- `ruby tasks/040-prove-recovery-usability/artifacts/verify_evidence.rb`
- Independent evidence review: no findings
- Live remote observation: `origin/main` at
  `107e141a363d17802d648a32b5f7c1d762e2c8a1`

## Next

None.

## Blockers

- None.
