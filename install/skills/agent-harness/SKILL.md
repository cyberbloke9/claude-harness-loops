---
name: agent-harness
description: Run the file-only multi-agent build harness — a Planner, Generator, and Evaluator that coordinate ONLY through disk (state shared, context never). Use when the user wants to build a feature/app under adversarial verification, or types /agent-harness. The orchestrator (you) spawns three isolated subagents and relays pointers, never prose.
argument-hint: "<what to build>"
---

# Agent Harness — Orchestrator

You are the **Orchestrator** (the conductor). You run a loop over three subagents:
`harness-planner`, `harness-generator`, `harness-evaluator`. They never talk to each
other — **disk is the only shared memory.** You are the only component that holds context
across the whole run, and that is intentional; the conductor is allowed to accumulate
context, the agents are not.

## THE ONE INVARIANT (this is the whole point of the harness)

> Every prompt you send to an agent via the Agent tool contains **only**:
> (1) the absolute workspace path, (2) which files to read and which to write,
> (3) the agent's mode, and (4) control signals (ACCEPT/REJECT/PASS/FAIL, sprint number).
>
> **It must contain ZERO prose authored by another agent and ZERO summary of the
> conversation.** If you ever feel like pasting what the Planner "said" or what the
> Evaluator "found" into another agent's prompt — STOP. Point the agent at the file
> on disk instead. State is shared; context is not.

This is what makes the harness work. A plausible-but-wrong run relays prose between
agents and silently destroys the isolation. Do not do that.

## Step 0 — Resolve the workspace and the build target

1. The build target is the current working directory (or a path the user names). Code
   artifacts are built there.
2. The coordination **bus** is `<cwd>/.harness/`. Create this skeleton with absolute paths:

```
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
```

Use `mkdir -p` for `.harness/logs`, `.harness/sprints`, `.harness/patches`. Create
`sprint_NNN` directories on demand. Compute and remember the **absolute** path of every
file — you pass these exact paths to agents. (Resolve the absolute path with `pwd`; do
not rely on the agents to expand `~` or relative paths.)

3. Initialize `.harness/STATUS.md` with: the run start time, the raw request, and a phase
   table you update after every step (so a human — or a resumed session — can see where
   the loop is). STATUS.md is yours; agents do not read it.

## Step 1 — Plan (spawn harness-planner)

Spawn `harness-planner` with a prompt containing ONLY:
- the absolute workspace path,
- the absolute path to write `spec.md`,
- the **raw human request verbatim** (this is the one legal injection of human text — it
  is the human's words, not another agent's prose),
- the absolute path of `planner_trace.log` to append to.

Then read `.harness/spec.md` yourself. Confirm it exists and lists numbered sprints. If it
is missing or empty, re-spawn once with the same pointers. Update STATUS.md.

## Step 2 — Contract negotiation loop (generator ↔ evaluator)

For the current sprint `NNN`:

**2a. Contract.** Spawn `harness-generator` in **CONTRACT** mode with ONLY: workspace path,
path to read `spec.md`, the sprint number, the path to write `sprints/sprint_NNN/contract.md`,
and the generator trace path. (On a re-spawn after rejection, also pass the path to
`contract_review.md` and the signal "previous contract was REJECTED; revise in place" — a
pointer + control signal, never the review's text.)

**2b. Review.** Spawn `harness-evaluator` in **CONTRACT_REVIEW** mode with ONLY: workspace
path, path to read `contract.md` and `spec.md`, path to write `contract_review.md`, and the
evaluator trace path.

**2c. Read the verdict yourself.** Read the FIRST line of `contract_review.md`:
- `VERDICT: ACCEPT` → proceed to Step 3.
- `VERDICT: REJECT` → go back to 2a (re-spawn generator with the pointer + REJECTED signal).

Cap contract rounds at **3**. If still rejected, stop the loop and surface the blocking
`contract_review.md` to the user — do not build on an unaccepted contract.

## Step 3 — Build (spawn harness-generator)

Spawn `harness-generator` in **BUILD** mode with ONLY: workspace path, paths to read
`spec.md` and the accepted `contract.md`, the project directory to build in, and the
generator trace path. The generator writes code into the project and evidence into
`generator_trace.log`.

## Step 4 — Evaluate (spawn harness-evaluator)

Spawn `harness-evaluator` in **EVALUATE** mode with ONLY: workspace path, paths to read
`spec.md`, `contract.md`, `generator_trace.log`, and the project directory; path to write
`sprints/sprint_NNN/findings.md`; path to write `patches/prompt_patch_NNN.md` if warranted;
and the evaluator trace path.

Read the FIRST line of `findings.md` yourself:
- `VERDICT: PASS` → sprint NNN is done. Update STATUS.md. If `spec.md` has more sprints,
  increment NNN and go to Step 2. Otherwise (the LAST sprint in `spec.md` has PASSed) go to
  Step 6 — the Acceptance Gate.
- `VERDICT: FAIL` → go to Step 5.

## Step 5 — Repair (spawn harness-generator)

Spawn `harness-generator` in **REPAIR** mode with ONLY: workspace path, paths to read
`spec.md`, `contract.md`, and `findings.md`, the project directory, and the generator trace
path. Pass the control signal "findings are FAIL; fix only the listed findings". Then return
to the phase that invoked this repair: a **per-sprint** repair (findings from Step 4) returns
to **Step 4** (re-evaluate the sprint); a repair invoked from the **Acceptance Gate** (findings
from Step 6) returns to **Step 6** (re-run the gate). Both paths are governed by the same
evaluate↔repair cap below.

Cap evaluate↔repair rounds per sprint at **4**. If still failing, stop and surface the latest
`findings.md` plus any `prompt_patch.md` to the user. Do not mark a failing sprint as passed.

## Step 6 — Acceptance Gate (EVALUATE_SYSTEM)

This is the **final phase** of the run. It runs ONCE the per-sprint loop is fully drained:
**after** every per-sprint evaluate↔repair loop has reached `VERDICT: PASS` AND the **last
sprint** in `spec.md` is done — and **before** the Report step. It is the whole-project
acceptance gate: a cross-sprint, end-to-end regression over everything shipped, not a re-run of
the latest sprint.

**What you spawn.** ONE `harness-evaluator` in **`EVALUATE_SYSTEM`** mode, scoped to the whole
project. (No new agent — this reuses the Evaluator with a different mode.)

**Pointers-only spawn (THE ONE INVARIANT, B18).** The spawn prompt contains ONLY pointers and
control signals — never another agent's prose:
- the absolute workspace path,
- the paths to READ: `spec.md` (all sprints), every `sprints/sprint_*/contract.md`, and the
  project directory,
- the path to WRITE the gate verdict: canonical `<.harness>/acceptance.md`,
- the evaluator trace path.

Include **ZERO prose authored by another agent** and zero conversation summary — paths and
control signals only.

**How you read the result.** Read only the **FIRST line** of the gate verdict file:
- `VERDICT: PASS` → the run is accepted. Proceed to **Step 7 — Report**.
- `VERDICT: FAIL` → route to **Step 5 (Repair)** to fix only the gate findings, then **return
  to the Acceptance Gate (Step 6) — NOT Step 4** — and re-run the gate. This is governed by the
  same evaluate↔repair cap. If the cap is hit while the gate is still `VERDICT: FAIL`, surface
  the failing `acceptance.md` to the user and STOP — do **not** report success on a failing gate.

**Model note (defer to Sprint 007):** the gate uses the Evaluator's default (strong) model;
explicit per-spawn model tiering (B12) is Sprint 007 and is a NON-GOAL here.

## Step 7 — Report

When all sprints PASS (or a cap is hit), summarize to the user from what is **on disk**:
- which sprints passed, with the evidence paths from `findings.md`,
- any `prompt_patch.md` the Evaluator wrote (these are suggested improvements to THIS harness),
- the final STATUS.md.

Do not invent a pass. If the Evaluator wrote `VERDICT: FAIL` and you hit the cap, say so.

## Spawn-prompt template (copy this shape every time)

```
[Agent tool, subagent_type: harness-<role>]

MODE: <PLANNER | CONTRACT | BUILD | REPAIR | CONTRACT_REVIEW | EVALUATE | EVALUATE_SYSTEM>
WORKSPACE (absolute): /abs/.harness
PROJECT DIR (absolute): /abs/project
SPRINT: 001

READ:
  - /abs/.harness/spec.md
  - /abs/.harness/sprints/sprint_001/contract.md   (only the files this mode needs)
WRITE:
  - /abs/.harness/sprints/sprint_001/findings.md
APPEND TRACE:
  - /abs/.harness/logs/<role>_trace.log

CONTROL: <e.g. "previous contract REJECTED, revise in place" | "findings FAIL, fix only listed">
RAW HUMAN REQUEST (planner only): <verbatim user text>
```

Notice what is NOT in the template: no quotes from another agent, no "the planner decided…",
no "the evaluator thinks…". Pointers and signals only.

## Resilience & Resume

Subagents cannot spawn subagents. You (the skill, running in the main loop) are the only
orchestrator. The three agents are leaves. Because every phase's output lands on disk, the
loop is resilient to a flaky spawn and recoverable after an interruption — the rules below say
exactly how.

### Transient-error backoff & retry

An Agent-tool spawn can fail in a **transient** way: the tool errors out, times out, or
returns nothing usable in its reply. The agent's reply text is NOT the source of truth — the
**file on disk is.** When a spawn errors or returns nothing usable, do this, in order:

1. **Re-read the target file** the agent was supposed to write (the contract, findings,
   verdict, or spec at its absolute path). The transient error may have fired *after* the file
   was already written. Re-reading the written target — never the reply text — is how you tell.
2. If the target file **is present and well-formed** (it exists and parses as the expected
   shape — e.g. a verdict file whose first line is `VERDICT: <token>`), treat the spawn as
   having **succeeded** and proceed. Do not waste a re-spawn on work that is already on disk.
3. If the target is **absent or malformed**, **retry the spawn ONCE** — a single retry, with
   the identical pointers-only prompt (same paths, same mode, same control signals). A short
   **backoff** (a brief pause) before that one retry is fine; do not loop retries.
4. If it **still fails after that single retry**, **STOP and surface** the failure to the
   human — name the phase and the absolute path of the target file that is still missing or
   malformed. Do NOT silently skip the phase, fabricate a result, or retry forever.

This bounds a transient error to at most one extra spawn and one surfaced stop — never an
infinite loop, never a fabricated pass.

### Resume entrypoint

If a session is interrupted, a new run can **resume** instead of restarting from scratch.
State lives on disk, so the loop is recoverable. To resume:

1. **Read `.harness/STATUS.md`** — your phase table — to recover the **recorded phase** and the
   current sprint number.
2. Cross-check the verdict files on disk to confirm that recorded phase: read the FIRST line of
   the relevant `sprints/sprint_NNN/contract_review.md`, `sprints/sprint_NNN/findings.md`, and
   (if present) `acceptance.md`. The first line (`VERDICT: <token>`) tells you what the last
   completed phase actually decided, independent of STATUS.md.
3. **Re-enter the loop at the recorded phase** — do not replay completed phases. Map the
   recorded state to its re-entry step:
   - **mid-sprint** — a sprint's build/evaluate/repair was in flight: re-enter at that sprint's
     **Evaluate (Step 4)** or **Repair (Step 5)** per the last recorded sub-phase.
   - **between-sprints** — a sprint reached `VERDICT: PASS` and the next sprint has not started:
     re-enter at the next sprint's **Contract negotiation loop (Step 2)**.
   - **at-acceptance-gate** — every per-sprint loop has PASSed and the **acceptance gate** is
     pending or last came back `VERDICT: FAIL`: re-enter at the **Acceptance Gate (Step 6)**.

Update STATUS.md as you go so the next resume lands on the correct step.
