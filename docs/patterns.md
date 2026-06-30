# Patterns & Lineage

This file maps each mechanism of the claude-agent-harness to the public, citable
pattern it descends from. It is reference material, not a tutorial: **no external
repo is cloned** — each source is summarized and linked, so a maintainer or a
future agent can read *why* the harness is shaped this way and follow the link to
the primary source. Every claim below is tied to an observable mechanism in this
repo (an agent file, a SKILL section, or a `scripts/validate.sh` check); where a
mechanism is a pragmatic extension with no clean single source, it is labelled as
such and **not** given a fabricated citation (see "Honesty note on extensions").

The five lineages are: Anthropic *Building Effective Agents*, the Anthropic
*Claude Agent SDK* agent loop, humanlayer's *12-factor-agents*, the Claude Code
*subagent* best practice, and obra's *superpowers*.

---

## (S1) Anthropic — Building Effective Agents

> "In the orchestrator-workers workflow, a central LLM dynamically breaks down
> tasks, delegates them to worker LLMs, and synthesizes their results." …
> "In the evaluator-optimizer workflow, one LLM call generates a response while
> another provides evaluation and feedback in a loop."

Source: [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)
(Anthropic Engineering, 2024-12-19).

Two of its named workflow patterns are load-bearing in this harness:

- **orchestrator-workers** → the orchestrator (the `/agent-harness` skill driver)
  spawns three worker subagents — `harness-planner`, `harness-generator`,
  `harness-evaluator` — decomposes the build into sprints, and synthesizes their
  file outputs. The orchestrator relays **file pointers**, never a worker's prose
  (see the disk-only invariant in S3).
- **evaluator-optimizer** → the Generator↔Evaluator loop. The Evaluator reviews a
  contract (`CONTRACT_REVIEW`) and later attacks the build (`EVALUATE`), writing a
  verdict; the Generator optimizes against that verdict in BUILD/REPAIR. The loop
  iterates until the verdict is `ACCEPT`/`PASS`. The post itself notes this pattern
  fits "when we have clear evaluation criteria, and when iterative refinement
  provides measurable value" — which is exactly the per-sprint contract + findings
  cycle here.

---

## (S2) Anthropic — Claude Agent SDK agent loop

> "Claude often operates in a specific feedback loop: gather context → take action
> → verify work → repeat."

Source: [Building agents with the Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk)
(Anthropic; the post documents the renaming of the Claude Code SDK to the Claude
Agent SDK and the loop above; URL contains the `agent-sdk` slug).

The harness mirrors all three phases of that loop:

- **gather context** → each worker reads spec/contract/findings **from disk** at
  the start of its turn (the Generator reads `spec.md`, the sprint `contract.md`,
  and any `findings.md`; the Evaluator reads the contract + the built code).
- **take action** → the Generator builds exactly the accepted contract and writes
  physical evidence into `generator_trace.log`.
- **verify (work)** → the Evaluator's verify step: it attacks the build with real
  click/command paths and rules-as-code, and `scripts/validate.sh` is the harness's
  own machine-checkable "rules" verifier (LLM-as-judge + deterministic checks).

So the Generator's build-and-self-evidence cycle is *gather context → take action*,
and the Evaluator supplies the *verify work* that the Generator is forbidden from
self-certifying.

---

## (S3) humanlayer — 12-factor-agents

> "What are the principles we can use to build LLM-powered software that is
> actually good enough to put in the hands of production customers?"

Source: [12-factor-agents](https://github.com/humanlayer/12-factor-agents)
(humanlayer).

Three of its factors map directly onto harness mechanisms:

- **Factor: own your context window (stateless / file-only)** → agents coordinate
  **only through disk**. There is no agent-to-agent prose passing; the shared memory
  is files at fixed paths. This is the harness's core invariant (B18) and the single
  rule every enhancement is additive to.
- **Factor: structured outputs (tools/JSON, not prose)** → the Evaluator writes a
  machine-readable **verdict** header whose first line is exactly `VERDICT: <token>`,
  followed by `SCORE:`, `BLOCKERS:`, `HIGH:`. The orchestrator reads the header
  alone to branch — structured output instead of re-reading prose.
- **Factor: own your control flow** → the **STATUS.md** resume entrypoint. An
  interrupted build is re-entered at the recorded phase by reading
  `<project>/.harness/STATUS.md`; control flow is owned by the harness, persisted on
  disk, not implicit in a chat transcript.

---

## (S4) Claude Code — subagent best practice

> Subagents "run in their own context window with a custom system prompt, specific
> tool access, and independent permissions" and can be routed to "faster, cheaper
> models like Haiku" to control cost.

Source: [Create custom subagents](https://docs.claude.com/en/docs/claude-code/sub-agents)
(Claude Code docs; the canonical path is `claude-code/sub-agents`).

Two mechanisms descend from this page:

- **capability isolation via `tools:` frontmatter** → the `harness-evaluator`
  agent's `tools:` list **omits `Edit`**, so the Evaluator is *physically* incapable
  of building what it judges. This is capability over instruction: enforced by
  frontmatter and statically asserted by `scripts/validate.sh` check (e), not by
  asking the agent nicely.
- **per-subagent `model` field for tiering** → the docs' "control costs by routing
  to faster, cheaper models" is the basis for per-spawn model tiering: the
  orchestrator downshifts the model for the Evaluator's `CONTRACT_REVIEW` spawn only,
  while frontmatter keeps the strong model (`opus`) as the default. (Deep cost
  treatment is deferred — see the Honesty note.)

---

## (S5) obra — superpowers

> "An agentic skills framework & software development methodology that works."

Source: [superpowers](https://github.com/obra/superpowers) (obra).

One mechanism descends from this layout:

- **progressive disclosure** → `SKILL.md` stays lean and points to `docs/`
  reference files (this file, `operating_loop.md`, `file_protocol.md`) that are
  loaded on demand rather than inlined into every prompt. The skills-as-reference
  layout — a thin skill that discloses detail progressively — mirrors superpowers'
  composable-skills approach and keeps the operating prompt small.

---

## Mechanism → pattern mapping

Each harness mechanism, the pattern it descends from, the source, and where it is
enforced in this repo:

| Harness mechanism | Source pattern | Lineage | Enforced / located in |
|---|---|---|---|
| Orchestrator + worker agents (planner/generator/evaluator) | orchestrator-workers | S1 | `install/agents/*.md`, `install/skills/agent-harness/SKILL.md` |
| Evaluator / contract-review loop | evaluator-optimizer | S1 | `harness-evaluator.md` (`CONTRACT_REVIEW`/`EVALUATE`), generator REPAIR mode |
| Build-and-verify worker cycle | gather context → take action → verify | S2 | generator BUILD + `generator_trace.log`; evaluator verify; `scripts/validate.sh` |
| File-only / disk coordination | own-your-context / stateless | S3 | core invariant B18; everything under `.harness/` on disk |
| Structured **verdict** header | structured outputs | S3 | `harness-evaluator.md` verdict-header section; `validate.sh` check (g) |
| Capability isolation (`tools:` omits `Edit`) | subagent tool access | S4 | `harness-evaluator.md` `tools:`; `validate.sh` check (e) |
| Per-spawn model tiering (cheap for `CONTRACT_REVIEW`) | subagent `model` routing | S4 | SKILL.md "Model selection per spawn"; `validate.sh` check (i) |
| **Progressive disclosure** (lean skill → `docs/`) | progressive disclosure | S5 | `SKILL.md` + this `docs/` tree |
| **STATUS.md** resume entrypoint | own-your-control-flow | S3 | SKILL.md "Resilience / Resume"; `validate.sh` check (c) |

---

## Honesty note on extensions

Not every mechanism has a clean single public source. These are pragmatic
extensions, labelled as such and **not** given a fabricated citation:

- **Model-tiering rubber-stamp backstop.** Routing the Evaluator's `CONTRACT_REVIEW`
  to a cheaper model risks a "rubber-stamp" (a weak model accepting a thin
  contract). The backstop — keeping every other phase on the strong model, plus the
  strong final acceptance gate — is a risk-mitigation we adopted for *this* harness;
  the cheaper-model idea is sourced (S4), but the specific backstop policy is ours,
  not a cited pattern. Its deeper cost/risk treatment is deferred to
  `docs/token-economy.md` (Sprint 010); this file only names it and points forward,
  to avoid duplicating that doc.

When in doubt, the rule is: cite what is genuinely sourced, label what is ours.
