# Tighten Runtime Boundaries

## Goal

Make scheduler projections, worktree location, and authentication configuration
match their documented runtime contracts across separate server and OpenCode
processes.

## Source Evidence

- Scheduler-facing lifecycle responses use the broad task serializer and expose
  description Markdown plus the complete workflow definition.
- The scheduler contract says it never receives task Markdown or workflow
  artifacts for dispatch.
- `kos-git` needs `<kos-data-home>`, while client installation does not define
  how a nondefault server data home is shared with OpenCode.
- Server and CLI validate bearer-token header suitability differently.
- See task 018's `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Introduce focused scheduler response projections for create/get, claim,
  resumable selection, and resume operations.
- Keep full step instructions and task Markdown available only through the
  executor context path.
- Define one explicit client-side worktree-root contract that works when Rails
  and OpenCode have separate environments, without storing machine-local paths
  in project domain state.
- Align server and CLI token validation for valid HTTP bearer-header values.
- Add cross-process configuration and projection tests.

## Out Of Scope

- Per-agent authorization, multiple tokens, or remote worktree hosts.
- Persisting checkout or worktree paths in projects.
- Changing task content or workflow instructions.

## Acceptance Criteria

- Scheduler operations return only fields required to select, claim, resume,
  stop, and retain the task ID.
- Scheduler test evidence proves Markdown and workflow bodies are absent from
  actual responses, not only forbidden by prompt text.
- An installation with a nondefault data home derives the same verified
  worktree path in Rails documentation and OpenCode execution.
- Any token accepted by the server is usable by the packaged CLI as an HTTP
  header value, and invalid values fail before boot or request.
- No project row stores a machine-local filesystem path.
- `bin/check` passes.
