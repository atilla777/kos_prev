# Plan

1. Define the smallest project-scoped plan and task listing projections needed
   for recovery.
2. Add authenticated API reads and thin CLI commands with stable filtering and
   error behavior.
3. Update the orchestrator skill to inspect unfinished state before creating or
   replacing a plan.
4. Test fresh-session discovery of pending, active, paused, and completed work,
   including restart persistence.
5. Update public documentation and run `bin/check`.
