# Installation

Install the Rails service, CLI gem, built-in catalog, and OpenCode integration
from one checked-out Git revision. Mixed revisions are unsupported because step
context, artifact reporting, profiles, and workflow outcomes are one protocol.

## Prerequisites

- Ruby 3.4.10 and Bundler 4.0.20;
- SQLite 3 with development headers;
- Git; and
- OpenCode 1.18.26 or later with credentials for the configured models.

## Server And CLI

Check out the release, configure a local persistent data home and bearer token,
install dependencies, and prepare the database:

```sh
git fetch --tags
git checkout <release-tag-or-commit>
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="$(openssl rand -hex 32)"
bundle check || bundle install
bin/rails db:prepare
```

`KOS_DATA_HOME` must be an absolute local path outside the checkout, not a
synchronized or network-mounted directory. Database preparation installs the
canonical `brief`, `development`, and `fix` task types and workflows. It does
not register a project.

Build and install the exact CLI revision outside the checkout, then retain its
absolute path:

```sh
gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
"$KOS_CLI_PATH" --version
"$KOS_CLI_PATH" --help
```

## OpenCode Inventory

Install the managed integration from the same checkout:

```sh
bin/install-opencode
```

The default destination is `$XDG_CONFIG_HOME/opencode`, or
`~/.config/opencode`. `--config-home <absolute-path>` selects an isolated or
nonstandard destination. The installer copies this exact inventory:

- commands: `kos.md`, `kos-fix.md`, and `kos-brief.md`;
- focused agents: `kos-diagnose.md`, `kos-plan.md`, `kos-implement.md`,
  `kos-document.md`, `kos-brief.md`, `kos-review.md`, `kos-publish.md`, and
  `kos-verify.md`;
- custom-step agents: `kos-step-standard.md` and `kos-step-advanced.md`; and
- skills: `kos`, `kos-brief`, `kos-cli`, `kos-create`, `kos-step`, `kos-git`,
  and `okf`.

The installer removes obsolete managed `kos-orchestrator.md` and `kos-step.md`
agent profiles. It refuses symlinked or wrongly typed managed destinations.
`kos-create` is a focused pre-ID scheduler skill, not an agent profile. Slash
commands run in the primary `build` agent under the user's main-agent permission
policy; the installed focused profile files apply only after ID-only dispatch.

The shipped mapping uses `openai/gpt-5.6-terra` with medium reasoning for
standard implementation, documentation, publication, generic standard steps,
and `/kos` or `/kos-fix` scheduling. It uses `openai/gpt-5.6-sol` with high
reasoning for diagnosis, planning, briefing, review, verification, generic
advanced steps, and `/kos-brief` scheduling. Administrators may substitute
complete `provider/model-id` values while preserving these authority roles.
Check availability with `opencode models openai`.

Restart OpenCode after every installation or profile, command, skill, or model
change. A running OpenCode process does not reload this inventory.

## Configure And Register

Start Rails with the same data home and token:

```sh
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="http://127.0.0.1:3000"
bin/rails server
```

In another terminal, expose the same API and installed CLI, verify readiness,
and explicitly register the repository:

```sh
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="http://127.0.0.1:3000"
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
curl --fail "$KOS_API_URL/up"
"$KOS_CLI_PATH" project create \
  --name "My project" \
  --remote-url "https://github.com/example/my-project.git" \
  --repository-identity "github.com/example/my-project" \
  --default-branch "main"
"$KOS_CLI_PATH" project show \
  --repository-identity "github.com/example/my-project"
```

The registration identity must exactly match the canonical identity derived
from the invoking checkout's single `origin` fetch and push URLs. Equivalent
supported SSH and HTTPS URLs normalize to the same identity. A missing,
ambiguous, malformed, or mismatched origin blocks before task or worktree
mutation. There are no `KOS_PROJECT_*` environment variables.

After restarting OpenCode, verify discovery of `/kos-brief`, `/kos`, and
`/kos-fix`. Verify that the installed CLI help includes `task context`, `task
artifact`, and `task report-attempt` with `--artifact-file`. The installation is
not ready until those focused operations and all managed profiles and skills
come from the same revision.

## Upgrade

Stop Rails and active schedulers, check out one new revision, rebuild and
install the gem, reinstall OpenCode integration, migrate and seed, then restart
Rails and OpenCode:

```sh
gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
bin/install-opencode
bin/rails db:prepare
bin/rails db:seed
```

Built-in bootstrap reuses identical definitions and creates immutable workflow
revisions when definitions change. Existing tasks retain IDs, relationships,
workflow snapshots, lifecycle position, and derived worktrees.

When upgrading unfinished pre-state-oriented tasks, their accepted-artifact map
starts empty. For an unfinished built-in task whose immutable snapshot predates
the `verify` step, first preserve all worktree changes, then cancel that task and
recreate the work on the current built-in catalog. Do not try to publish it,
repoint its workflow, import it, or run old and current definitions in parallel.
For a task already on a current snapshot, rerun its authoritative current step
to reconstruct missing accepted evidence. Do not copy or import old local
`tasks/<id>/<step>.md` files or answer sidecars; current agents never read them.

## Verify

Run `bin/check` in the release checkout; it proves automated lifecycle and
installed-asset contracts. Separately, required deployment release evidence
uses live models and isolated state and repositories to run real `/kos-brief`,
`/kos`, and `/kos-fix` commands through publication and independent
verification. Confirm completed tasks, released ownership, accepted artifacts
in KOS, expected remote commits, and the brief child graph. Passing `bin/check`
alone is not evidence that those live command executions occurred.
