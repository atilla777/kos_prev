---
name: okf
description: Read or change product behavior specifications in a project's specs/ Open Knowledge Format v0.2 bundle.
---

# Product Specifications In OKF

Use this skill when a workflow step reads or changes product behavior in the
exact project worktree's `specs/` bundle. Do not use it for plans, architecture,
test strategy, task state, commits, or publication.

## Boundary

Refuse a symlinked bundle root or any path that escapes it. Read or write only
paths below `specs/`; other repository files may be read as evidence.

## Read And Edit

Read `specs/index.md` first, then follow relevant links and search the bundle for
affected concepts. Each concept is a UTF-8 Markdown file other than `index.md`
or `log.md`, starts with YAML frontmatter, and has a nonempty string `type`.

Preserve unknown metadata, unrelated body content, and existing organization.
Keep affected indexes and links accurate. Prefer bundle-relative links between
concepts. Add only evidence-supported product behavior; do not invent optional
metadata or claim implementation and checks exist without evidence.

For a `Product Specification`, use only the relevant sections from Goal, Actors,
User Scenarios, Rules, Errors, Edge Cases, Acceptance Criteria, and Non-goals.
Link to technical documents instead of duplicating them.

## Verify

Verify concept frontmatter, changed links and indexes, preservation of unrelated
content, and confinement to product behavior. If sources materially conflict,
ask one precise question through the calling workflow.
