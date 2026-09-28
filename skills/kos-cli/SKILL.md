---
name: kos-cli
description: Discover and safely invoke the public KOS CLI as a thin client.
---

# KOS CLI

Use the absolute executable in `KOS_CLI_PATH`. `KOS_API_URL` selects the server;
`KOS_API_TOKEN` is required except for `health`, `installation check`, and local
`claim-id`. Never print the token or bypass the CLI with HTTP, Rails, or database
access.

Use `--help` and per-command help for the installed interface. The commands are
`health`, `claim-id`, `installation check`, `project create/show/update`,
`workflow create/list/show/schema`, `plan put/list/show/abandon`, and `task
list/ready/show/context/result/claim/takeover/report/answer`. Run `installation
check` before a KOS workflow; it verifies the OpenCode manifest, CLI, and server
release identity and server readiness. `KOS_OPENCODE_MANIFEST` may select a
non-default absolute manifest path.
`plan abandon` is fenced by the observed plan version. List commands return
non-completed state, including terminal abandoned records; use
`--include-completed` for successful history.
Common signatures are `project show --repository-identity IDENTITY`, `workflow
list [--key KEY]`, `workflow show ID`, `workflow schema`, `plan list
--project-id ID`, `plan show --project-id ID --key KEY`, `task list --project-id
ID`, `task ready --project-id ID`, `task show ID`, and `task context ID`.
`workflow schema` and `workflow create --help` provide the authoritative
definition shape and complete example. Task discovery returns the selected
workflow ID, key, and revision.
Pass each value as a separate argument. Send plans, workflow definitions,
results, and answers with the
documented file options; use `-` for standard input when convenient.

For ordinary mapped operations, exit `0` is an HTTP success and `1` is an HTTP
failure with the unchanged server body on stdout. `installation check` instead
uses exit `1` and a structured stderr error for server unavailability or release
mismatch. Exit `2` is a usage/configuration/input or local installation error on
stderr, and `3` is a transport error on stderr. KOS state is authoritative after
an ambiguous mutation; do not convert transport or server errors into workflow
outcomes.
