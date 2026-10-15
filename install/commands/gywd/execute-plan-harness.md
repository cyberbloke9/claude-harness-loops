---
name: GYWD:execute-plan-harness
description: Execute a GYWD ROADMAP milestone (or a single phase) through the agent-harness adversarial loop — the harness Planner turns the milestone + its requirements into a phases-1:1-sprints spec, then Contract→Build→Attack→Gate runs per sprint
argument-hint: "[milestone name/version, a phase number, or 'current']"
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
Execute a GYWD **ROADMAP milestone** (a range of phases) — or a single phase — using the
**agent-harness** as the execution backend, so every phase is built and signed off by an
**isolated, hostile grader (`VERDICT: PASS`)** before the next, instead of GYWD's default
`execute-plan`, where the builder also writes its own SUMMARY (self-certification).

This is the bridge in `docs/DESIGN-gywd-integration.md`. It COMPOSES the two systems:
- **GYWD owns** the planning layer — `ROADMAP.md` (the milestone + its phases) and the
  requirements doc the milestone names (e.g. `V3.md`), plus `PROJECT.md`/`RESEARCH.md` for
  context, and the returned `SUMMARY`/`STATE.md`/ROADMAP checkboxes/commits.
- **The harness owns** execution: the **Planner** turns the milestone into a `spec.md` with
  **one sprint per ROADMAP phase (1:1)**, then the standard per-sprint loop
  (Contract → context-isolated BUILD → adversarial EVALUATE → Repair) and the final
  **Acceptance Gate** run — reusing the EXISTING harness agents (no new agents here).

**The seam (grounded in real runs, e.g. pocket-decision-book v3.0).** GYWD users drive the
harness at the *milestone* level: a ROADMAP milestone block says *"Requirements: <file>. Phases
map 1:1 to harness sprints"* and lists its phases; the harness Planner reads that + the
requirements doc and writes a milestone `spec.md` whose Sprints 001..00N are those phases. This
command automates exactly that handoff. It does NOT read GYWD `plan-phase` `PLAN.md` files — that
per-phase artifact is optional and most GYWD runs skip it; if a phase does have a `PLAN.md`, it is
read as extra per-phase detail, never as the unit of work.

**State split (authoritative):**
- `.planning/STATE.md` + `.planning/ROADMAP.md` (GYWD) = **project position** — which milestone/
  phase, decisions, session; the ROADMAP phase checkboxes are the durable progress record.
- `<project>/.harness/STATUS.md` (harness) = **in-flight sprint phase** — contract/build/evaluate/
  gate. Ephemeral per run; reconciled INTO STATE.md + ROADMAP checkboxes at each sprint PASS.
</objective>

<context>
Target: $ARGUMENTS  (a milestone name/version like `v3.0`, a single phase number like `12`, or
`current` — if omitted, use the current milestone from `.planning/STATE.md`/`ROADMAP.md`).

**Load first:**
@.planning/STATE.md
@.planning/ROADMAP.md

One ROADMAP **phase** = one harness **sprint**. A milestone of N phases = an N-sprint `spec.md`
run end to end. (A single-phase target is just the N=1 case.)
</context>

<process>

**1. Preflight (stop with a clear message if any fails).**
- `.planning/ROADMAP.md` exists (else: "run /gywd:create-roadmap first").
- The target milestone (or phase) resolves to a concrete set of ROADMAP phases.
- The harness agents are installed — the `Task` tool can spawn `harness-planner`,
  `harness-generator`, `harness-evaluator`. If not, tell the user to run the harness `install.sh`.
- **Resume guard (check this FIRST, before any bus setup).** If `<project>/.harness/STATUS.md`
  exists and shows an in-flight run of THIS milestone (any sprint without a terminal verdict, or a
  phase in `building`/`evaluating`), DO NOT start a new run — hand off to
  `/agent-harness-resume <project>` instead. Starting fresh here would rebuild already-passed work
  and clobber the live bus. Only proceed past this step for a genuinely new milestone or a clean prior one.

**2. Resolve the milestone and its inputs (YOU do this in the main context).**
- From `ROADMAP.md`, extract the target milestone's **phase list** (each `- [ ] **Phase N — …**`
  line, with its one-line scope and its `Verify:` criteria if present) and the milestone's
  **`Requirements:`** pointer (e.g. `.planning/V3.md`), which is authoritative when phases carry no
  inline `Verify:`.
- Determine which phases are already **done** vs **todo**. A phase counts as done if its ROADMAP
  box is `- [x]` **OR** its sprint's `.harness/sprints/sprint_00k/findings.md` first line is
  `VERDICT: PASS` (ROADMAP checkboxes are sometimes left unticked during a manual run — the verdict
  on disk is the source of truth, per "if it is not written to disk it does not exist"). Only todo
  phases become sprints to run; done phases are context, not work. If every target phase is already
  done, there is nothing to build — report that and stop.

**3. Set up the harness bus.**
- Project dir = the repo root where `.planning/` lives. Create `<project>/.harness/` (+ `sprints/`,
  `logs/`, `patches/`) if absent.
- If a `.harness/` from a *prior, completed* milestone exists (its sprints all PASSED — the resume
  guard in Step 1 already ruled out an in-flight one), preserving its contents is a **destructive,
  confirm-first action**: show the user what you would move (e.g. rename to `.harness-<prevver>/`)
  and wait for approval before touching it. Never silently overwrite a bus.

**4. Plan → `spec.md` via the harness Planner (DO NOT hand-translate; DO NOT skip the Planner).**
Spawn `harness-planner` (model: `opus`) with ONLY pointers: the project dir; the paths to read —
`ROADMAP.md` (scoped to the target milestone's phases), the milestone's requirements doc
(`V*.md`), and `PROJECT.md`/`RESEARCH.md` for context; the path to write `.harness/spec.md`; and
the instruction that **each todo ROADMAP phase becomes exactly one sprint (1:1), in order**. The
sprint's contract-testable bar comes from that phase's ROADMAP `Verify:` criteria **when present,
otherwise it is derived from the requirements doc** — not every ROADMAP annotates phases with
`Verify:` (a milestone may point all detail at its `V*.md`), and the requirements doc is
authoritative for the bar. Then read the spec yourself only enough to confirm: one `Sprint 00k`
per todo phase, in phase order.

**5. Run the standard harness loop over the spec's sprints.**
For each sprint in order, follow the main `/agent-harness` SKILL.md loop verbatim:
- **CONTRACT** (opus) → **CONTRACT_REVIEW** (cheap: `haiku`, or the optional external-review
  bridge `bash ~/.claude/skills/agent-harness/scripts/external_review.sh <contract.md> <spec.md>
  <contract_review.md>` when `HARNESS_EXTERNAL_REVIEW=1`, with the mandatory fallback) → on
  ACCEPT → **BUILD** (opus) → **EVALUATE** (opus) → on FAIL, **REPAIR** (opus) and re-EVALUATE.
- Read only the FIRST `VERDICT:` line of each verdict file. Caps: contract rounds 3, build↔repair
  rounds 3. On an unrecovered FAIL, STOP: surface the blocking verdict; do not advance.

**6. Acceptance Gate (EVALUATE_SYSTEM, opus)** after the last sprint PASSes — a whole-milestone
end-to-end regression → `<project>/.harness/acceptance.md`. A gate FAIL routes to Repair and
re-runs the gate, same as Step 5.

**7. Return to GYWD — after EACH sprint PASS, and once at milestone end.**
- Per sprint PASS: write/append the GYWD `SUMMARY` for that phase from the harness `findings.md`
  evidence (what was built, how verified, commit hashes); **tick the ROADMAP phase** (`- [ ]` →
  `- [x]`); update `.planning/STATE.md` position.
- **Commit per GYWD's rules** — individual `git add` of the files that sprint touched (NEVER
  `git add -A`). **Match the project's existing commit convention** (read `git log --oneline -10`
  first; do not invent one — e.g. this repo's runs use `feat(v3-s001): … (Phase 11)`), then a docs
  metadata commit for the planning artifacts. Push only if GYWD's config/your norms allow it
  (a push is a stop-and-confirm action unless already authorized).
- At milestone end: all target phases `- [x]`, acceptance gate PASSED, STATE.md advanced to the
  next milestone. Tell the user `/gywd:verify-work` remains the human UAT sign-off, now after an
  automated gate.

</process>

<deviation_rules>
GYWD's `execute-plan` auto-fixes bugs/blockers in-flight. Under the harness the Generator is
contract-bound, so in-flight discoveries do NOT become silent edits:
- correctness/security gaps the Evaluator finds → the REPAIR loop (Step 5);
- scope a phase genuinely missed → a **contract addendum** (amend the sprint `contract.md`,
  re-review) or, if it is really a planning miss, stop and route to `/gywd:plan-phase` /
  `/gywd:discuss-phase` for that phase.
This preserves the harness's "the contract is truth" guarantee while keeping GYWD's intent.
</deviation_rules>

<success_criteria>
- [ ] Target milestone's todo phases resolved from `ROADMAP.md` + its `Requirements:` doc read
- [ ] `.harness/spec.md` produced by the **Planner** with one sprint per ROADMAP phase (1:1, in order)
- [ ] Each sprint ACCEPTED (cheap tier) then PASSED under adversarial EVALUATE (strong tier)
- [ ] Whole-milestone Acceptance Gate PASSED
- [ ] Per sprint: `SUMMARY` written from harness evidence, ROADMAP phase ticked `- [x]`, files
      committed per GYWD's individual-staging rules; `.planning/STATE.md` reconciled
- [ ] On any unrecovered FAIL: milestone left incomplete, blocking verdict surfaced, nothing faked
</success_criteria>
