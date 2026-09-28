---
name: kos-cli
description: Discover and safely invoke the public KOS CLI as a thin client.
---

# KOS CLI

Use the absolute executable in `KOS_CLI_PATH`. `KOS_API_URL` selects the server;
`KOS_API_TOKEN` is required except for `health` and local `claim-id`. Never print
the token or bypass the CLI with HTTP, Rails, or database access.

Use `--help` and per-command help for the installed interface. The commands are
`health`, `claim-id`, `project create/show/update`, `workflow create`, `plan
put/list/show`, and `task list/ready/show/context/result/claim/takeover/report/answer`.
List commands return unfinished state by default; use `--include-completed` for
deliberate historical inspection. Pass each value as a separate argument. Send
plans, workflow definitions, results, and answers with the documented file
options; use `-` for standard input when convenient.

Exit `0` is an HTTP success, `1` is an HTTP failure with the unchanged server
body on stdout, `2` is a usage/configuration/input error on stderr, and `3` is a
transport error on stderr. KOS state is authoritative after an ambiguous
mutation; do not convert transport or server errors into workflow outcomes.
