# Token Economy

This file codifies the claude-agent-harness's token-minimization and
prompt-caching discipline, plus the model-tiering rubber-stamp risk and its
backstop. It is **reference material, not a tutorial**: each technique states
*what* it is and *why* it lowers token/cost spend, with an observable criterion
where one exists. Where a technique is guidance the harness *gives to the apps it
builds* (rather than something the harness repo itself runs), it is labelled as
such — see "Applies to the harness vs. applies to Generator-built apps" below.

The companion file `docs/patterns.md` maps these mechanisms to their public
source patterns; this file is the cost-and-tokens view of the same machinery.
The README / operating-loop write-ups of the gate, resume, and tiering land in a
later sprint (B17) — this file only points at those mechanisms, it does not
duplicate them.

---

## Applies to the harness vs. applies to Generator-built apps

The harness repo is a CLI / markdown / bash tooling repo. It performs **no vision
step and makes no LLM inference calls of its own** — the Claude reasoning happens
inside the Claude Code agents that *run* the harness, not in any code committed
here. So the six topics split into two groups:

- **Harness mechanisms (T1, T2, T3, T6)** — these are how *this* harness keeps
  spend low and are observable in the agent files, the `SKILL.md`, and
  `scripts/validate.sh`.
- **Guidance for Generator-built apps (T4, T5)** — image downsampling and
  prompt-caching are advice the harness hands to the applications a Generator
  builds *when those apps do vision or LLM calls*. The harness itself neither
  downsamples images nor sets `cache_control`; do not read T4/T5 as claims that
  it does.

---

## (T1) Pointers-not-prose spawns

The orchestrator relays **file paths and control signals between agents — never
another agent's prose** (this is the B18 disk-only coordination invariant). When
the Planner finishes a `spec.md`, the orchestrator tells the Generator *where the
file is*, not *what it says*; when the Evaluator writes `findings.md`, the
orchestrator routes the Generator to that path.

The token win is structural: a pointer is **O(bytes) regardless of how large the
pointed-to artifact is**. A path like `/abs/.harness/spec.md` costs a few dozen
tokens whether the spec is 2 KB or 200 KB. Pasting the artifact's prose into the
next spawn instead re-pays the artifact's full token cost **on every relay** —
and an agent loop relays many times, so the prose cost compounds linearly with
the number of hand-offs while the pointer cost stays flat.

Observable criterion: the orchestrator's spawn payloads contain paths, not
quoted file bodies; coordination state lives on disk, and that invariant is what
check (e)'s capability isolation and the disk-only design protect.

---

## (T2) Verdict header / first-line-only reads

The Evaluator writes a **machine-readable header** atop every verdict file
(Sprint 004, B9). The header's first line is exactly `VERDICT: <token>`, followed
by `SCORE:`, `BLOCKERS:`, and `HIGH:` lines. The orchestrator routes the loop by
reading **only that header / first line** — it does not ingest the whole
`findings.md` body to decide PASS vs. FAIL or to count blockers.

The token win: routing needs four short lines, so the orchestrator pays four
lines of input instead of the entire findings file (which can run to many
kilobytes of reproduction steps and evidence). The full body is read only when a
human or an agent actually needs the detail — not on every routing decision.

This relies on the back-compatible header schema defined in the Evaluator agent
spec (validated by check (g)); this file names that mechanism by reference and
does not duplicate its schema.

---

## (T3) Lean prompts + progressive disclosure

`SKILL.md` stays lean; the detail lives in `docs/` files that are **loaded on
demand**. The operating loop, the acceptance-gate phase, the resilience/resume
protocol, and the model-tiering rule are stated compactly in the skill; the
deep-dives (this file, `docs/patterns.md`) are separate documents a reader or
agent opens only when a task needs them. This mirrors the obra/superpowers
progressive-disclosure lineage recorded in `docs/patterns.md`.

The token win: the **fixed context stays small**. Every spawn pays the lean
`SKILL.md`, and pays for a reference doc only when the task at hand requires it —
detail is pay-per-use rather than pay-always. Bloating `SKILL.md` with every
edge case would tax every single spawn for content most spawns never use.

Observable criterion: required `SKILL.md` sections are enforced by check (c)
(operating loop, acceptance gate, resilience/resume), while the lengthy
rationale lives in `docs/` — not inlined into the skill.

---

## (T4) Image downsampling for vision (guidance for Generator-built apps)

**This is guidance for Generator-built apps that use a vision model. The harness
repo has no vision step.**

When full resolution is not needed, downsample images to **≤1024px on the long
edge, client-side, before sending** them to a vision model. Image tokens scale
with resolution: a vision model tiles an image and charges tokens per tile, so a
larger image costs proportionally more input tokens. Capping the long edge at
1024px caps the tile count, and therefore caps the per-image token cost, before a
single token is billed.

The criterion is observable in the app's request: downsample on the client so the
bytes that leave the app are already small — resizing *after* upload saves
nothing because the model has already been charged for the full-resolution image.
Only skip downsampling when the task genuinely needs the extra detail (dense
documents, fine print, small UI targets); otherwise the ≤1024px cap is the
default.

---

## (T5) Prompt-caching guidance for Generator-built apps

**This is guidance for Generator-built apps that make Claude API calls. The
harness repo makes no such calls.** The parameters below are the real, current
Anthropic API surface (consulted from the `claude-api` skill, not invented).

A Generator-built app that re-sends a large stable prefix (a long system prompt,
a fixed tool list, a retrieved document) on many requests should cache that
prefix:

- **Breakpoint.** Mark the last block of the stable prefix with
  `"cache_control": {"type": "ephemeral"}`. The `cache_control` field with an
  `ephemeral` cache type is what tells the API to cache up to that point. An
  optional one-hour TTL is `"cache_control": {"type": "ephemeral", "ttl": "1h"}`
  (the default TTL is five minutes).

- **The prefix-match invariant (load-bearing).** Prompt caching is a **prefix
  match**: any byte change anywhere in the prefix invalidates everything after
  it. Render order is `tools` → `system` → `messages`. So keep **stable content
  first** (a frozen system prompt, a deterministically-ordered tool list) and put
  **volatile content last** (per-request timestamps, UUIDs, the user's varying
  question) — *after* the last `cache_control` breakpoint. A `datetime.now()` in
  the system prompt, an unsorted `json.dumps`, or a per-user tool set silently
  invalidates the cache on every request.

- **How to verify a cache hit.** Read the response usage fields:
  `usage.cache_read_input_tokens` (tokens served from cache, billed at roughly
  0.1× the base input rate) and `usage.cache_creation_input_tokens` (tokens
  written to the cache, billed at roughly 1.25× for the 5-minute TTL). If
  `cache_read_input_tokens` stays **zero across repeated identical-prefix
  requests**, a silent invalidator is at work — that zero is the observable
  signal to audit the prefix for a per-request change.

The economics: a cache read costs ~0.1× the base input price and a 5-minute
cache write costs ~1.25×, so a stable prefix re-used even a couple of times pays
for its write. The exact field and type tokens — `cache_control`, `ephemeral`,
`cache_read_input_tokens` — are copy-pasteable verbatim because they are the
documented API surface.

---

## (T6) Model-tiering rubber-stamp risk + backstop

**The risk (R3).** The harness uses a cheaper / faster model for **exactly one**
spawn: the Evaluator's `CONTRACT_REVIEW` (Sprint 007, B12). Downshifting the
model saves tokens-as-cost on contract review, but a cheaper model could
**rubber-stamp** a weak contract — accept a contract that a stronger model would
have rejected — letting an under-specified contract through to BUILD.

**The backstop.** The cheap model is **never** extended to any other phase. The
strong model still runs:

- the **strong per-sprint `EVALUATE`** — which adversarially attacks the actual
  built behavior, so a weak contract that slipped through review is caught when
  the work is evaluated against a hostile user; and
- the **strong final acceptance gate** (`EVALUATE_SYSTEM`) — a cross-sprint
  end-to-end regression run at full model strength.

Together these catch what a cheap contract-review would miss: the cost saving is
ring-fenced to the one phase where a strong downstream gate exists to absorb a
rubber-stamp, and the downshift is **CONTRACT_REVIEW only**. The agent files keep
the strong model as their frontmatter default (validated by check (i)), so the
cheap tier cannot leak into a default.

---

## Summary

| Topic | Applies to | Token win |
|------|------------|-----------|
| T1 pointers-not-prose | harness | pointer is O(bytes); prose re-pays per relay |
| T2 verdict-header read | harness | route on 4 header lines, not the whole findings file |
| T3 lean prompts + progressive disclosure | harness | fixed context small; detail pay-per-use |
| T4 image downsampling ≤1024px | Generator-built apps | caps per-image tile/token cost |
| T5 prompt caching | Generator-built apps | cached prefix billed ~0.1× on reads |
| T6 model tiering + backstop | harness | cheap model on CONTRACT_REVIEW only, strong gates absorb the risk |
