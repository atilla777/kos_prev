# Status

State: planned
Updated: 2026-09-26

## Current

The scheduler rereads context after execution but does not require progress
before dispatching the same step again. Expired active claims also lack an
in-loop recovery path.

## Next

After task 018 is done, define the bounded progress contract and add an
executable failing scheduler scenario before changing guidance.

## Blockers

Depends on task 018.

## Checks

Not started.
