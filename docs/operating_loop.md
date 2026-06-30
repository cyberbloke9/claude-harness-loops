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

## Phase 8: Acceptance Gate

The **Acceptance Gate** is the final phase of a run. It runs once the per-sprint loop is
fully drained — after the last sprint in `spec.md` reaches `VERDICT: PASS`, and before the
report. It is not a re-run of the latest sprint; it is a whole-project check.

The orchestrator spawns **one** `harness-evaluator` in **`EVALUATE_SYSTEM`** mode, scoped to
the whole project, for a cross-sprint, end-to-end regression over everything shipped. The
spawn carries pointers only (workspace path, the files to read, the path to write the gate
verdict `acceptance.md`) — never another agent's prose.

The orchestrator reads only the first `VERDICT:` line of the gate verdict (`acceptance.md`):

- `VERDICT: PASS` → the run is accepted; proceed to the report.
- `VERDICT: FAIL` → route to Repair (Phase 6) to fix only the gate findings, then **re-run
  the Acceptance Gate** — not the per-sprint Evaluate phase. The same evaluate↔repair cap
  applies; if the cap is hit while the gate is still `VERDICT: FAIL`, surface the failing
  `acceptance.md` and stop. A failing gate is never reported as a pass.

## Resume

Because every phase writes its output to disk, an interrupted run can **resume** instead of
restarting. To resume:

1. Read `.harness/STATUS.md` — the orchestrator's phase table — to recover the recorded phase
   and the current sprint number.
2. Cross-check the on-disk verdict files (the first `VERDICT:` line of the relevant
   `contract_review.md`, `findings.md`, and `acceptance.md`) to confirm what the last
   completed phase actually decided, independent of `STATUS.md`.
3. Re-enter the loop at the recorded phase — do not replay completed phases. The three resume
   states map as follows:
   - **mid-sprint** (a sprint's build/evaluate/repair was in flight) → re-enter at that
     sprint's Evaluate or Repair phase.
   - **between-sprints** (a sprint reached `VERDICT: PASS`, the next has not started) →
     re-enter at the next sprint's Contract negotiation loop.
   - **at-acceptance-gate** (every per-sprint loop has PASSed; the gate is pending or last
     returned `VERDICT: FAIL`) → re-enter at the Acceptance Gate.

A transient spawn error is handled the same way the file-first rule implies: re-read the
target file (it may already be written), retry the spawn once if it is absent or malformed,
then surface the failure — never an infinite retry, never a fabricated result.

## Model selection per spawn (tiering)

The orchestrator overrides the Agent-tool `model` field **per spawn**. The agent frontmatter
keeps the **strong** model (`opus`) as the default, so a spawn that sets nothing already runs
strong. The strong tier is used for the high-stakes phases — Generator `BUILD`, Generator
`CONTRACT` drafting, Evaluator `EVALUATE`, and Evaluator `EVALUATE_SYSTEM` (the Acceptance
Gate). A **cheaper/faster** model is downshifted for **`CONTRACT_REVIEW` only** — that single
phase, and no other.

The risk of a cheaper reviewer is that it could **rubber-stamp** a weak contract. The
backstop: a rubber-stamped contract is re-attacked downstream by the strong `EVALUATE` and by
the strong `EVALUATE_SYSTEM` acceptance gate, so the downshift is bounded to the
cheapest-to-recover step. The full write-up lives in `docs/token-economy.md`.

## Structured verdict header

Every verdict file (`contract_review.md`, `findings.md`, `acceptance.md`) opens with a
machine-readable header whose **first line is exactly `VERDICT: <token>`** — this first-line
format is back-compatible, and existing parsing relies on it. The header continues with
`SCORE:`, `BLOCKERS:`, and `HIGH:` lines.

The orchestrator routes on the **header / first line only** — it reads the `VERDICT:` token to
decide the next step and never parses the whole verdict file to route. Reading only the first
line is the token-economy win: the routing decision costs a single line, not the full document.
