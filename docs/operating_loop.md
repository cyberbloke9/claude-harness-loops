# Operating Loop

## Phase 1: Planning

The Planner receives the human request and writes `spec.md`.

The spec should be high-level but concrete enough to guide product direction.

The Planner must not over-prescribe implementation details unless they are essential.

## Phase 2: Contract Negotiation

The Generator reads `spec.md` and writes `sprint_contract.md` for one sprint only.

The Evaluator reviews the contract before any code is written.

The contract must pass before implementation starts.

## Phase 3: Generation

The Generator implements only the accepted sprint contract.

The Generator must not silently expand scope.

The Generator writes:

- code changes
- migration notes if any
- test commands
- self-reported risks
- implementation summary

## Phase 4: Evaluation

The Evaluator runs adversarial checks.

Required checks:

- Open the live app.
- Click through real user flows.
- Test happy paths.
- Test failure paths.
- Check responsive layouts.
- Inspect console errors.
- Look for stubs, placeholders, and fake data.
- Grade design, originality, craft, functionality, security, and accessibility.

## Phase 5: Findings

The Evaluator writes `findings.md`.

Each finding must include:

- Severity.
- Exact reproduction steps.
- Expected behavior.
- Actual behavior.
- Evidence.
- Required fix.
- Pass condition.

## Phase 6: Repair

The Generator fixes only the listed findings unless a fix reveals a blocking dependency.

New work requires a new sprint contract.

## Phase 7: Prompt Debugging

If the same class of failure repeats, update the harness.

The Evaluator writes `prompt_patch.md` explaining:

- What the agents failed to catch.
- Why the current prompt or rubric allowed it.
- What prompt change would prevent recurrence.
