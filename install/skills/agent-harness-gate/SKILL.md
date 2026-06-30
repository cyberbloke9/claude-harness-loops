---
name: agent-harness-gate
description: Runs the Acceptance Gate (EVALUATE_SYSTEM) on a finished project — spawns ONE harness-evaluator scoped to the whole project, writes <project>/.harness/acceptance.md, and reads only its first VERDICT line. Use after a build to re-attack everything shipped, on demand, without re-running the whole loop.
argument-hint: "<project> (absolute path to the finished project; defaults to cwd)"
allowed-tools: Task, Read, Bash, Glob, Grep
---

# Agent Harness — Acceptance Gate (standalone)

You are running the **Acceptance Gate** on an already-finished project, on demand. This is a
thin standalone entrypoint into the harness's final phase: a whole-project, cross-sprint,
end-to-end regression over everything shipped — **without** re-running the per-sprint build
loop. It reuses the existing Evaluator in **`EVALUATE_SYSTEM`** mode (no new agent).

## THE ONE INVARIANT (B18 — restated inline)

When you spawn the Evaluator below, the spawn prompt contains **only pointers and control
signals**: absolute paths to read, the absolute path to write, the mode, and control signals.
It contains **ZERO prose authored by another agent and ZERO conversation summary.** If you
ever feel like pasting what another agent "said" or "found", STOP and point at the file on
disk instead. State is shared; context is not. Every spawn this skill makes obeys this.

## Steps

1. **Resolve `<project>`** to an absolute path — the argument, or `pwd` (via `Bash`) if it is
   omitted. Confirm `<project>/.harness/` exists (`Bash`/`Glob`). If there is **no `.harness/`**
   (nothing was ever built here), say plainly **"nothing built; nothing to gate"** and **stop**.
   Do **not** fabricate a gate verdict.

2. **Spawn ONE `harness-evaluator` in `EVALUATE_SYSTEM` mode** via the **`Task`** tool, scoped to
   the whole project. The spawn prompt is **pointers + control signals only** (the invariant
   above):
   - `MODE: EVALUATE_SYSTEM`
   - the absolute **workspace** path: `<project>/.harness`
   - the paths to **READ**: `<project>/.harness/spec.md`, every
     `<project>/.harness/sprints/sprint_*/contract.md`, and the project directory itself
   - the path to **WRITE** the gate verdict: `<project>/.harness/acceptance.md`
   - the evaluator **trace** path: `<project>/.harness/logs/evaluator_trace.log`

   Use the **strong** model for this spawn — the Acceptance Gate is one of the strong-tier
   phases (set the `Task` tool's `model` field to the strong tier, e.g. `opus`). See the main
   skill's `## Model selection per spawn` for the full per-spawn rule.

3. **Read only the FIRST line** of `<project>/.harness/acceptance.md` (`Read`/`Bash`):
   - `VERDICT: PASS` → report the run **accepted** and give the evidence path (`acceptance.md`).
   - `VERDICT: FAIL` → report the gate **failed** and point the user at `acceptance.md` for the
     specific findings. Do **not** invent a pass.

## Reference (do not duplicate)

For the full Acceptance-Gate semantics — when it runs, the FAIL→Repair→re-gate routing, and the
evaluate↔repair cap — see **`## Step 6 — Acceptance Gate (EVALUATE_SYSTEM)`** in the main
`agent-harness/SKILL.md`. This entrypoint points at that section rather than restating it.
