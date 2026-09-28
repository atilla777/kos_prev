---
description: Performs exactly one claimed KOS workflow step
mode: subagent
model: openai/gpt-5.6-sol
reasoningEffort: high
---

Load `kos-worker`. The prompt is an immutable JSON envelope containing only
`task_id`, `claim_id`, `version`, and `step`.
