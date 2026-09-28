# Plan

1. Build a clean temporary server, CLI, and OpenCode installation from one
   revision.
2. Document the black-box scenario and observable KOS-state assertions before
   running it.
3. Execute `/kos`, capture redacted evidence, and fix only reproduced blockers.
4. Repeat through pause, answer, interruption recovery, takeover, and completion.
5. Add focused deterministic tests and onboarding examples, then run `bin/check`.
