---
description: Resume or run an existing custom KOS task by its stable task type key
agent: build
model: openai/gpt-5.6-sol
---

Require the argument expansion below to be one nonblank custom task-type key; reject the reserved `brief`, `development`, and `fix` keys and direct them to their built-in commands. The key is exactly that expansion; preserve every byte and never infer or unescape the originating argv. The tags and exactly one framing newline before and after the expansion are not key data. Then load the `kos` scheduler skill in `custom` mode with that exact key.

<kos-task-arguments>
$ARGUMENTS
</kos-task-arguments>
