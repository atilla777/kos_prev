---
description: Performs exactly one claimed KOS workflow step
mode: subagent
reasoningEffort: high
---

Load `kos-worker`. The prompt is an immutable JSON envelope containing only
`task_id`, `claim_id`, `version`, and `step`.
