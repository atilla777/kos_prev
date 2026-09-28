# Status

State: done
Updated: 2026-09-28

## Result

- Added authenticated `workflow list`, `workflow show`, and `workflow schema`
  CLI operations over the existing immutable revision API.
- Shared workflow validation, schema output, limits, and the complete example
  through packaged pure-Ruby contract code.
- Made common command help identify required values, identifiers, exact input
  and response shapes, and ready-to-use examples.
- Added selected workflow key and revision to task discovery and actionable
  missing workflow, plan, task, and result diagnostics without changing the
  `not_found` discriminator.

## Decisions

- Expose existing workflow reads rather than asking agents to guess keys.
- Make schema output derive from the same contract as validation rather than
  maintaining an independent prose-only schema.
- Preserve immutable revisions and stable error discriminators.

## Checks

- Focused model, API, CLI, package, and skill tests passed.
- `bin/check` passed: 108 tests, 1610 assertions, no failures.
- Independent review identified four help, schema, diagnostic, and package-smoke
  gaps. All were corrected; two follow-up passes reported no findings.

## Residual Risk

The declarative schema and procedural validation share one module and constants,
but future changes must continue extending both representations together.
