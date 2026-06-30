---
name: agent-harness-resume
description: Resumes an interrupted harness run — reads <project>/.harness/STATUS.md, cross-checks the VERDICT first lines on disk, and re-enters the loop at the recorded phase without replaying completed phases. Use to recover a build that was interrupted instead of restarting from scratch.
argument-hint: "<project> (absolute path to the interrupted project; defaults to cwd)"
allowed-tools: Task, Read, Bash, Glob, Grep
---

# Agent Harness — Resume (standalone)

You are recovering an **interrupted** harness run from disk. State lives on disk, so the loop is
recoverable: instead of restarting from scratch, you re-enter at the **recorded phase**. This is
a thin standalone entrypoint into the harness's resume path; it spawns the same
Generator/Evaluator subagents the main loop does.

## THE ONE INVARIANT (B18 — restated inline)

Every re-entry spawn you make below carries **only pointers and control signals**: absolute
paths to read, the absolute path to write, the mode, and control signals. It carries **ZERO
prose authored by another agent and ZERO conversation summary.** If you feel like pasting what
another agent "said" or "decided", STOP and point at the file on disk instead. State is shared;
context is not.

## Steps

1. **Resolve `<project>`** to an absolute path — the argument, or `pwd` (via `Bash`) if omitted.
   **Read `<project>/.harness/STATUS.md`** — the orchestrator's phase table — to recover the
   **recorded phase** and the current sprint number. If `STATUS.md` is **missing**, say plainly
   **"nothing to resume"** and **stop** (there is no recorded state to recover).

2. **Cross-check the verdict files on disk** (independent of `STATUS.md`). Read the **FIRST line**
   (`VERDICT: <token>`) of the relevant `sprints/sprint_NNN/contract_review.md`,
   `sprints/sprint_NNN/findings.md`, and — if present — `acceptance.md`. The first line tells you
   what the last completed phase actually decided, so a stale or half-written `STATUS.md` cannot
   send you to the wrong step.

3. **Re-enter the loop at the recorded phase** — do **not** replay completed phases. Map the
   recorded state to its re-entry step. Each re-entry spawns a Generator/Evaluator subagent via
   the **`Task`** tool, pointers-only per B18 above, using the per-spawn `model` rule:
   - **mid-sprint** (a sprint's build/evaluate/repair was in flight) → re-enter at that sprint's
     **Evaluate (Step 4)** or **Repair (Step 5)**, per the last recorded sub-phase.
   - **between-sprints** (a sprint reached `VERDICT: PASS` and the next has not started) →
     re-enter at the next sprint's **Contract negotiation loop (Step 2)**.
   - **at-acceptance-gate** (every per-sprint loop PASSed; the gate is pending or last came back
     `VERDICT: FAIL`) → re-enter at the **Acceptance Gate (Step 6)**.

   Update `STATUS.md` as you go so the next resume lands on the correct step.

## Reference (do not duplicate)

For the full phase definitions and the resume protocol — including the transient-error backoff &
retry rule — see **`## Resilience & Resume`** (and its `### Resume entrypoint` block) in the main
`agent-harness/SKILL.md`. This entrypoint points at that section rather than restating it.
