# Focused Live Evidence

Date: 2026-09-27
Operational source identity:
`sha256:a2a9f8e807d155369efc681fdd2ead046ce4d7a5df15a9df3e3bd1118690a664`

## Isolation

The run used an isolated production database, data home, packaged CLI, OpenCode
configuration, fixture checkout, task worktree, SSH transport, and bare remote.
The installed server, CLI, and OpenCode inventory came from the changed working
tree. Retained evidence contains no API token, model transcript, or session ID.

## Scenario

One real `/kos` command claimed a development task to add a `--whisper` greeting
mode. The initial implementation attempt reported `blocked` because the fixture
lacked a Git author identity and its isolated gem path omitted `minitest`. After
those fixture prerequisites were supplied, the same task resumed through the
public fenced operation and completed.

Authoritative accepted artifacts were exactly:

| Step | Outcome | Claim version | Evidence |
| --- | --- | --- | --- |
| `plan` | `planned` | 1 | Advanced subagent |
| `implement` | `implemented` | 4 | Standard subagent, `required_checks: passed` |
| `review` | `approved` | 5 | Independent advanced subagent |
| `publish` | `published` | 6 | Standard subagent |

There was no `document` step or artifact. The successful implementation moved
directly to `review`, updated `specs/greeting.md` before review, and reported
`bin/check` passing with 5 runs and 51 assertions. Independent review reran the
same check and approved the product specification and complete aggregate diff.

The task completed at claim version 7 with released ownership. Publication
observed exact remote tip `440bedad70e857cee9a682c34e4f49928335e03e`, based on
`aa287ffb70634b5b52172d7100c9bbe3868e1d88`, with binary diff SHA-256
`408ed042ad4c588eedf5a7bda6047961aa847e6fd836bf73ebf7914ac16d3b24`.
The commit has exactly one `KOS-Task: 1` trailer and changes `bin/greet`,
`lib/greeting.rb`, `specs/greeting.md`, and `test/greeting_test.rb`.

The sanitized authoritative projections are retained as `live-task.json`,
`live-implement.json`, `live-review.json`, and `live-publish.json`.
`fixture-remote.bundle` is a self-contained copy of the observed remote and
passes `git bundle verify`. Together they independently expose the reduced
artifact sequence and bind its reviewed and published commit to remote history.
