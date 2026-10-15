# DESIGN — GYWD × Agent-Harness integration + external-LLM review bridge

Status: **APPROVED — implemented; seam CORRECTED 2026-10-15 (see below); offline-validated against
the live pocket-decision-book v3.0 run.**
Author: harness maintainer. Dates: designed 2026-07-06, seam corrected 2026-10-15.
Decisions locked by user: standalone command (not a flag); STATE.md=position / STATUS.md=in-flight;
external review = echo-stub / local-only for now; source tracked in the public harness repo, command
installed locally into GYWD's namespace like GYWD itself.

## CORRECTION (2026-10-15) — the real seam is the ROADMAP milestone, not `PLAN.md`

The original design (§2–§5 below, kept for history) assumed the seam was GYWD `plan-phase` output —
a per-phase `PLAN.md` → one sprint. **Evidence from the user's real runs disproves that.** On
`pocket-decision-book` (built GYWD→harness, 6+ sprints passed):
- `.planning/phases/` is **empty** — zero `PLAN.md`, zero `SUMMARY.md`. `plan-phase` was never used.
- The ROADMAP milestone block literally reads: *"Requirements: .planning/V3.md. Phases map 1:1 to
  harness sprints,"* and lists Phases 11–15.
- `.harness/spec.md` was *"Written by the Planner … Sprints 001–005 map to ROADMAP.md Milestone v3.0
  Phases 11–15"* — one milestone spec, phases 1:1 sprints, run through the standard harness loop.

So the real seam is **`ROADMAP.md` milestone (phase range) + the `V*.md` it names →
`harness-planner` → `spec.md` (phases 1:1 sprints) → standard per-sprint loop + Acceptance Gate.**
The original bridge was wrong twice: it read the wrong artifact (`PLAN.md`) and **skipped the
Planner**. The corrected command (`install/commands/gywd/execute-plan-harness.md`) reads the ROADMAP
milestone + requirements, **uses the Planner**, maps each ROADMAP phase to one sprint, and reconciles
back by ticking ROADMAP checkboxes + STATE.md per sprint PASS. `PLAN.md`, if present for a phase, is
optional extra detail — never the unit of work. Where §2–§5 say "PLAN.md", read "ROADMAP milestone +
requirements doc, via the Planner."

**Offline validation:** feeding ROADMAP Phases 11–15 + `V3.md` through the corrected command's
process reproduces the v3.0 decomposition (5 todo phases → Sprints 001–005, in order, each carrying
its `Verify:` criteria) — matching the hand-run `spec.md`/`STATUS.md` that already PASSED. No build
run, no project risk. See `scripts/validate_seam_offline.sh` notes in the commit.

This doc is grounded in the *actual* current behavior of both systems (files read, not assumed):
- GYWD commands: `~/.claude/commands/gywd/{plan-phase,execute-plan,challenge,verify-work,discuss-phase}.md`
  and workflow refs under `~/.claude/get-your-work-done/`.
- Harness: `~/.claude/skills/agent-harness/SKILL.md` (`## Model selection per spawn`, `## Resilience & Resume`),
  `~/.claude/agents/harness-{planner,generator,evaluator}.md`.

---

## 0. Guiding principle — compose, don't fuse

Do **not** melt the two systems into one blob. Keep GYWD as the **outer planning/PM layer** and the
harness as a **pluggable execution backend**. They already have clean, complementary strengths and
one overlapping seam (execution + verification). The integration is a *single new execution path*,
not a rewrite of either system. This respects the harness's own rule (Anthropic: "add complexity only
when it demonstrably improves outcomes") and GYWD's `.planning/` conventions.

---

## 1. What each system actually is (verified)

### GYWD (pmp-gywd) — the outer PM layer
```
new-project     → PROJECT.md          (deep context)
create-roadmap  → ROADMAP.md          (milestones / phases)
discuss-phase   → {phase}-CONTEXT.md  (human vision, collaborative)
research-phase  → research notes
plan-phase      → PLAN.md             ← THE SEAM (objective, context, tasks, verification,
                                        success_criteria, confidence scores)
execute-plan    → subagent builds AND writes its own SUMMARY.md, STATE.md, per-task commits
challenge       → on-demand adversarial agents (Critic/Devil's-Advocate/Red-Team/Chaos) — attacks the PLAN
verify-work     → manual UAT; the HUMAN tests, Claude only guides + logs to ISSUES.md
+ memory, drift detection, decision extraction, snapshots/rollback, GitHub sync, health
```
Execution strategies in `execute-plan.md`: A (fully autonomous subagent), B (segmented w/ verify
checkpoints), C (decision-dependent, main context).

**GYWD's weakest link (the thing worth replacing):** in `execute-plan`, the *same* subagent that
builds also **writes its own SUMMARY** — it self-certifies. Independent adversarial verification is
**optional and out-of-loop** (`challenge` is a separate command; `verify-work` is manual human UAT).
Nothing forces a hostile, isolated grader to sign off before a plan is marked complete.

### Agent-harness — the inner adversarial build engine
```
Planner   → spec.md
per sprint: CONTRACT → CONTRACT_REVIEW(cheap/haiku) → BUILD(opus) → EVALUATE/attack(opus)
Acceptance Gate → EVALUATE_SYSTEM(opus, cross-sprint end-to-end)
```
Non-negotiables: agents share **only disk** (context isolation); the Generator is **forbidden to
certify its own work**; the Evaluator has **no Edit tool** (capability isolation) and must write a
machine-readable `VERDICT: PASS` before the loop advances; model tiering + resilience/resume.

**The harness's strongest asset (the thing worth injecting into GYWD):** *automated adversarial
verification wired into the build loop as a hard gate.*

---

## 2. The seam — `PLAN.md` is already spec-shaped

`plan-phase.md` success criteria say each PLAN.md carries: **objective, execution_context, context,
tasks, verification, success_criteria, output, confidence scores.** That is nearly a 1:1 match for a
harness `spec.md` + a single sprint contract. And GYWD deliberately keeps plans small (2–3 tasks),
which maps naturally to **one PLAN.md → one harness sprint** (avoids multi-sprint orchestration
complexity entirely).

### Translation contract (GYWD → harness)
| PLAN.md field | Harness artifact |
|---|---|
| `objective` + `context` | `spec.md` product goal + constraints |
| `tasks` (2–3) | the sprint's **contract deliverables** (exact files + behaviors) |
| `verification` + `success_criteria` | the contract's **adversarial checklist** = the Evaluator's acceptance bar |
| `confidence scores` | informational; low confidence *may* trigger a pre-run `research-phase` (out of scope for v1) |

### Return contract (harness → GYWD)
| Harness artifact | GYWD artifact |
|---|---|
| `findings.md` (VERDICT/SCORE/BLOCKERS/HIGH + evidence) | `SUMMARY.md` body + commit hashes |
| per-sprint `VERDICT: PASS` | trigger GYWD's per-plan commit + STATE.md update |
| `VERDICT: FAIL` after cap | surface; **do not** mark the plan complete (mirrors GYWD's "don't fake done") |

**Key decision — the bridge SKIPS the harness Planner.** `plan-phase` already did the planning. The
bridge starts at the **Contract** phase, seeding the contract from `PLAN.md`. No double-planning; each
system owns its layer.

---

## 3. Ownership boundaries (no duplication)

| Concern | Owner |
|---|---|
| PROJECT.md, ROADMAP.md, phases, memory, drift, decisions, GitHub sync, human vision, UAT | **GYWD** |
| Contract, context-isolated BUILD, in-loop adversarial EVALUATE, Acceptance Gate, model tiering, resilience | **Harness** |
| `PLAN.md` (GYWD→harness) and `SUMMARY.md` / `STATE.md` (harness→GYWD) | **Shared disk contract** |

- **`challenge`** = *plan-time* adversary (attacks PLAN.md before build). **Harness Evaluator** =
  *build-time* adversary (attacks the built code after). Complementary, no conflict. `challenge`
  stays an optional pre-execution step.
- **`verify-work`** = human final sign-off, now running **after** an automated gate has already
  passed → smaller UAT surface, not eliminated.

---

## 4. Proposed flow

```
... unchanged through:  plan-phase → PLAN.md
[optional] /gywd:challenge PLAN.md        # plan-time adversary (existing)

/gywd:execute-plan --harness   →  BRIDGE:
   1. read PLAN.md + STATE.md
   2. create <project>/.harness/ bus; translate PLAN.md → spec.md + sprint contract
   3. run harness loop (reusing existing harness agents):
        CONTRACT_REVIEW (cheap: haiku OR external bridge — see Part B)
        BUILD           (opus)
        EVALUATE/attack (opus)
        [Acceptance Gate EVALUATE_SYSTEM if plan closes a phase]
   4. on PASS → write SUMMARY.md (from findings.md), update STATE.md, commit per GYWD's rules
      on FAIL after cap → surface; leave plan incomplete

verify-work → manual UAT (unchanged; now post-gate)
```

---

## 5. Implementation surface (for the LATER build — not now)

- **One new command**: `/gywd:execute-plan-harness` (or a `--harness` flag on `execute-plan`). A thin
  orchestrator that does the translation + drives the harness spawns + writes back GYWD state/commits.
- **Reuse existing harness agents** (`harness-generator`, `harness-evaluator`) — **no new agents.**
- **Reuse GYWD conventions** — `.planning/` state, per-plan commit format, ISSUES.md for deviations.
- **State reconciliation (must define to avoid drift):**
  - `STATE.md` (GYWD) = **project position** — which phase/plan, decisions, session.
  - `STATUS.md` (harness) = **in-flight sprint phase** — contract/build/evaluate/gate.
  - Bridge reconciles at plan completion: STATUS.md is ephemeral per-plan; STATE.md is the durable record.
- **Commit granularity:** one PLAN.md → one sprint → the build's file commits + GYWD's
  `docs({phase}-{plan})` metadata commit. (No mismatch because plan = sprint.)
- **Deviations:** GYWD's `execute-plan` auto-fixes bugs/blockers in-flight; the harness Generator is
  contract-bound. Resolution: in-flight discoveries become **REPAIR-loop items or a contract addendum**,
  never silent edits — preserves the "contract is truth" guarantee.

---

## 6. PART B — External (non-Claude) LLM review bridge

**Goal (user-selected):** let a genuinely external / cheaper model do the low-stakes phase, writing a
`verdict.md`-style file to disk — instead of a Claude `haiku` subagent.

### Why CONTRACT_REVIEW is the *only* right phase to externalize
- It is already the single downshifted phase (mechanical checklist) with a **strong-model backstop
  downstream** (EVALUATE + Acceptance Gate re-attack anything it let through). Provider risk is
  therefore *contained by design* — exactly where the user's instinct ("cheap model for low work") is safe.
- It is a **pure disk-in / disk-out function**: read `contract.md` + `spec.md` → write
  `contract_review.md`. No tools, no Edit, no multi-turn agency. A one-shot completion API suffices.
- By contrast, **BUILD / EVALUATE cannot leave the Claude-subagent model** — they need Bash + file
  tools + multi-turn agency. This is *why* externalizing only the low work is correct, and matches the
  Agent tool's constraint (its `model` field is Claude-only: `sonnet|opus|haiku|fable`).

### Design — a fallback-safe Bash bridge
`scripts/external_review.sh <contract.md> <spec.md> <out.md>`:
1. Build the CONTRACT_REVIEW checklist prompt (same bar the Evaluator uses).
2. Call an external provider via a configurable interface:
   - `HARNESS_REVIEW_CMD` — an arbitrary CLI that reads prompt on stdin, emits completion on stdout; **or**
   - OpenAI-compatible HTTP: `HARNESS_REVIEW_ENDPOINT`, `HARNESS_REVIEW_MODEL`, `HARNESS_REVIEW_KEY`.
3. Write the response to `<out.md>`, **enforcing** the structured header (line 1 = `VERDICT: ACCEPT|REJECT`).
4. **Validate the header. If malformed or the call fails → non-zero exit** so the orchestrator falls
   back to the proven `haiku` subagent (resilience: the disk contract is identical either way).

### Orchestrator hook (SKILL.md Step 2b)
> At CONTRACT_REVIEW: if `HARNESS_EXTERNAL_REVIEW=1` **and** the bridge script + creds are present,
> run the Bash bridge; else spawn the `haiku` subagent (default, back-compat). Read only line 1
> (`VERDICT:`) as today.

### Honest constraints (the "leaves the pure-subagent model" cost)
- The external model must reliably follow a structured-output instruction; tiny local models may not
  → the header-validation + fallback path is mandatory, not optional.
- Adds a **config/creds surface** (external key or local server). Never echo the key; keep in env /
  gitignored `.env` (consistent with the Generator's secrets-hygiene rule).
- **Experimental, off by default, env-gated** — the proven all-Claude path stays the default so this
  can never regress the harness.

### Keyless validation plan (before any real key)
- A local **echo-stub** `HARNESS_REVIEW_CMD` that returns a canned `VERDICT: ACCEPT` — proves the disk
  contract, header enforcement, and fallback logic with **no external dependency**.
- Then, optionally, a real run against an OpenAI-compatible endpoint if the user provides one.

---

## 7. Phased build plan (once approved)

**Phase 1 — Bridge (Part A):** `/gywd:execute-plan-harness`; PLAN.md→contract translator; drive
Build/Attack via existing agents; write SUMMARY.md/STATE.md + commits. Battle-test on **one** real
GYWD phase.
**Phase 2 — External review (Part B):** `scripts/external_review.sh` + SKILL.md Step 2b hook + env
gate; validate with the echo-stub (keyless), then optional real endpoint.
**Phase 3 — Docs + install:** update `operating_loop.md`, README, `install.sh`; re-run install.
Each phase gets the harness's own gate (dogfood) before the next.

---

## 8. Risks / open questions for your call

1. **New command vs flag** — a standalone `/gywd:execute-plan-harness` (clean, additive, zero risk to
   existing `execute-plan`) vs a `--harness` flag on `execute-plan` (fewer commands, but edits a
   proven file). *Recommendation: standalone command first.*
2. **State-file ownership** — confirm STATE.md=position / STATUS.md=in-flight split above.
3. **Which external provider** for Part B's optional real test (or keep it echo-stub / local-only)?
4. **GYWD is a local command suite, not a git repo** — do you want these changes tracked anywhere
   (e.g., a new `gywd-harness-bridge` folder in the public harness repo), or kept local like GYWD itself?

---

## 9. Non-negotiables preserved

Context isolation (agents share only disk), Generator-can't-self-certify, Evaluator-has-no-Edit,
verdict-first-line parsing, tiering, resilience — all untouched. The external bridge and the GYWD
path are **additive** and default-off / opt-in. Backward compatible.
