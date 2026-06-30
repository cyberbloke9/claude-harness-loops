# File-Only Coordination Protocol

## Prime Directive

Agents do not communicate through conversation. They communicate through files.

## Shared Files

The orchestrator passes the **absolute path** of every file to each agent. Agents never
hardcode or guess paths. This is the single canonical layout (it supersedes any older
naming in other docs):

| File (relative to `.harness/`) | Written By | Read By | Verdict token (first line) | Purpose |
|---|---|---|---|---|
| `spec.md` | Planner | Generator, Evaluator | — | Product intent and constraints |
| `sprints/sprint_NNN/contract.md` | Generator | Evaluator | — | Definition of done for one sprint |
| `sprints/sprint_NNN/contract_review.md` | Evaluator | Orchestrator → Generator | `VERDICT: ACCEPT` / `VERDICT: REJECT` | Contract approval or rejection |
| `sprints/sprint_NNN/findings.md` | Evaluator | Orchestrator → Generator | `VERDICT: PASS` / `VERDICT: FAIL` | Failures discovered after implementation |
| `logs/planner_trace.log` | Planner | All | — | Commands, outcomes, observations |
| `logs/generator_trace.log` | Generator | All | — | Commands, outcomes, observations |
| `logs/evaluator_trace.log` | Evaluator | All | — | Commands, outcomes, observations |
| `patches/prompt_patch_NNN.md` | Evaluator | Human / next run | — | Suggested harness changes |
| `STATUS.md` | Orchestrator | Human / resumed run | — | Loop phase tracking (not read by agents) |

The orchestrator (the `/agent-harness` skill) parses the first-line verdict token to route
the loop. Agents MUST start verdict files with the exact token.

## Rules

1. No agent may assume facts not present in files.
2. No agent may overwrite another agent's file without creating a new revision.
3. Every pass/fail decision must cite exact evidence.
4. Every build claim must include how it was verified.
5. Every failure must include reproduction steps.

## Canonical Directory Layout (the disk bus)

```txt
.harness/
  spec.md
  STATUS.md
  logs/
    planner_trace.log
    generator_trace.log
    evaluator_trace.log
  sprints/
    sprint_001/
      contract.md
      contract_review.md
      findings.md
  patches/
    prompt_patch_001.md
```

`.harness/` lives at the root of the project being built. Product code is written into the
project, not into `.harness/` — the bus holds only coordination state.

## Handoff Format

Each handoff must include:

- Current objective.
- Files read.
- Files written.
- Decisions made.
- Evidence gathered.
- Known risks.
- Next required action.
