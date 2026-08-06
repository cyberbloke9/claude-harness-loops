---
name: GYWD:execute-plan-harness
description: Execute a GYWD PLAN.md through the agent-harness adversarial loop (Contract→Build→Attack→Gate) instead of a self-certifying subagent
argument-hint: "[path-to-PLAN.md]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
  - AskUserQuestion
---

<objective>
Execute a GYWD `PLAN.md` using the **agent-harness** as the execution backend, so the build is
verified by an **isolated, hostile grader that must sign `VERDICT: PASS`** before the plan is
marked done — instead of GYWD's default `execute-plan`, where the same subagent that builds also
writes its own SUMMARY (self-certification).

This is the bridge described in `docs/DESIGN-gywd-integration.md`. It COMPOSES the two systems; it
does not fuse them:
- **GYWD owns** everything up to and including `PLAN.md` (roadmap→phase→plan), plus memory, drift,
  decisions, and the returned `SUMMARY.md`/`STATE.md`/commits.
- **The harness owns** Contract → context-isolated BUILD → adversarial EVALUATE → Acceptance Gate,
  with model tiering and resilience — reusing the EXISTING `harness-generator` / `harness-evaluator`
  agents (this command adds no new agents).

**State split (authoritative):**
- `.planning/STATE.md` (GYWD) = **project position** — which phase/plan, decisions, session. Durable.
- `<project>/.harness/STATUS.md` (harness) = **in-flight sprint phase** — contract/build/evaluate/gate.
  Ephemeral per plan; reconciled INTO STATE.md at plan completion.
</objective>

<context>
Plan path: $ARGUMENTS  (if omitted, auto-detect the current plan from `.planning/STATE.md`)

**Load first:**
@.planning/STATE.md

One GYWD `PLAN.md` maps to exactly **one harness sprint** — GYWD keeps plans small (2–3 tasks),
which is a single sprint's worth of work. No multi-sprint orchestration is needed here.
</context>

<process>

**1. Preflight (stop with a clear message if any fails).**
- `.planning/` exists (else: "run /gywd:new-project first").
- The target `PLAN.md` exists (arg, or the current plan from STATE.md).
- The harness agents are installed — the `Task` tool can spawn `harness-generator` and
  `harness-evaluator`. If not, tell the user to install the harness (`install.sh`).

**2. Set up the harness bus for this plan.**
- Choose the project dir = the repo root GYWD is operating on (where `.planning/` lives).
- Create `<project>/.harness/` and `<project>/.harness/sprints/sprint_001/` if absent.
- Derive a sprint id from the plan (e.g. `sprint_001`); a single plan = one sprint.

**3. Translate `PLAN.md` → harness inputs (YOU do this in the main context — cheap, no extra agent).**
Read the `PLAN.md` and write two files:
- `<project>/.harness/spec.md` — from the plan's `objective` + `context`: the product goal,
  constraints, and the states/behaviors that must exist. Keep the plan's pinned decisions verbatim.
- `<project>/.harness/sprints/sprint_001/contract.md` — from the plan's `tasks` + `verification` +
  `success_criteria`: the exact files to create/modify, the precise behavior contract, and an
  **adversarial contract-test checklist** (one row per success criterion / required state) plus the
  exact commands a verifier will run. This is the harness's normal `contract.md` shape — see
  `templates/` and `docs/file_protocol.md`. Do NOT invent scope beyond the plan; if the plan is
  ambiguous, surface it (GYWD's `discuss-phase`/`plan-phase` own clarification, not this bridge).
  > The bridge deliberately SKIPS the harness Planner and the Generator's CONTRACT-drafting step,
  > because `plan-phase` already planned. You seed the contract directly from `PLAN.md`.

**4. CONTRACT_REVIEW (cheap tier).** Spawn `harness-evaluator` in **CONTRACT_REVIEW** mode
(model: `haiku`) with ONLY pointers: workspace path, the `contract.md` + `spec.md` paths, the
`contract_review.md` write path. Read the FIRST line of `contract_review.md`:
- `VERDICT: ACCEPT` → go to step 5.
- `VERDICT: REJECT` → refine `contract.md` yourself against the review's blockers (or, if the gap is
  a planning gap, stop and route the user back to `/gywd:plan-phase`), then re-review. Cap at **2**
  rounds here; the plan already carries the design intent, so this should converge fast.
- *(Optional external reviewer: if `HARNESS_EXTERNAL_REVIEW=1` and a provider are configured, run
  `bash ~/.claude/skills/agent-harness/scripts/external_review.sh <contract.md> <spec.md>
  <contract_review.md>` for this one step instead of the haiku spawn — the installed absolute path,
  since the cwd is the user's project — with the mandatory fallback. See the main SKILL.md Step 2b.)*

**5. BUILD (strong tier).** Spawn `harness-generator` in **BUILD** mode (model: `opus`) with ONLY
pointers: workspace path, the `spec.md` + accepted `contract.md` paths, the project dir to build in,
and the generator trace path. It writes code + physical evidence to disk. Do NOT relay its prose.

**6. EVALUATE / attack (strong tier).** Spawn `harness-evaluator` in **EVALUATE** mode
(model: `opus`) with ONLY pointers: `spec.md`, `contract.md`, `generator_trace.log`, the project dir,
and the `findings.md` write path. Read the FIRST line of `findings.md`:
- `VERDICT: PASS` → go to step 7.
- `VERDICT: FAIL` → spawn `harness-generator` in **REPAIR** mode (opus) with the `findings.md` pointer
  + the REJECTED signal, then re-EVALUATE. Cap the build↔repair loop at **3** rounds. If still FAIL,
  STOP: surface `findings.md`, do NOT write SUMMARY, do NOT mark the plan complete.

**7. (If this plan closes a GYWD phase) Acceptance Gate.** Spawn `harness-evaluator` in
**EVALUATE_SYSTEM** mode (opus) to walk the whole phase end-to-end → `<project>/.harness/acceptance.md`.
A `VERDICT: FAIL` here blocks completion the same way step 6 does.

**8. Return to GYWD on PASS.**
- Write the GYWD `SUMMARY.md` for this plan from the harness `findings.md` evidence (what was built,
  how it was verified, the commit hashes) — use GYWD's summary template.
- **Commit per GYWD's rules** (individual `git add` of the files this plan touched; NEVER `git add -A`;
  commit message `{type}({phase}-{plan}): {task}`, then the `docs({phase}-{plan}): complete` metadata
  commit). The harness evidence lives under `.harness/` — include it or gitignore it per the repo's
  convention.
- **Reconcile state:** update `.planning/STATE.md` (GYWD position: plan complete, decisions, session).
  `.harness/STATUS.md` was the in-flight record and is now historical for this plan.
- Tell the user the plan passed under adversarial verification, and that `/gywd:verify-work` remains
  the human UAT sign-off (now running after an automated gate).

</process>

<deviation_rules>
GYWD's `execute-plan` auto-fixes bugs/blockers in-flight. Under the harness, the Generator is
contract-bound — so in-flight discoveries do NOT become silent edits. Instead:
- correctness/security gaps the Evaluator finds → the REPAIR loop (step 6);
- scope the plan genuinely missed → a **contract addendum** (amend `contract.md`, re-review) or, if
  it's really a planning miss, stop and route to `/gywd:plan-phase`.
This preserves the harness's "the contract is truth" guarantee while keeping GYWD's intent.
</deviation_rules>

<success_criteria>
- [ ] `.harness/spec.md` + `sprints/sprint_001/contract.md` faithfully translated from `PLAN.md`
- [ ] Contract ACCEPTED (cheap tier), build PASSED under adversarial EVALUATE (strong tier)
- [ ] (If the plan closes a phase) Acceptance Gate PASSED
- [ ] `SUMMARY.md` written from harness evidence; files committed per GYWD's individual-staging rules
- [ ] `.planning/STATE.md` reconciled (position advanced); `.harness/STATUS.md` reflects final phase
- [ ] On any unrecovered FAIL: plan left incomplete, blocking verdict surfaced, nothing faked
</success_criteria>
