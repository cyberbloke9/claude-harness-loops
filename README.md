# Claude Code Multi-Agent Harness

A small, strict, file-only harness for Claude Code builds, packaged as a **global skill +
three global agents** so it works in every session.

The goal is not more process. The goal is fewer false passes.

## Install (global, all sessions)

```bash
./install.sh            # copies the skill + agents into ~/.claude
./install.sh --uninstall
```

This installs:

- `~/.claude/skills/agent-harness/SKILL.md` — the orchestrator, invoked as `/agent-harness`
- `~/.claude/agents/harness-planner.md`, `harness-generator.md`, `harness-evaluator.md`

Set `CLAUDE_CONFIG_DIR` to install somewhere other than `~/.claude`.

## Use

In any project directory, in any Claude Code session:

```
/agent-harness build a habit tracker with streak history and a weekly heatmap
```

The orchestrator creates a `.harness/` directory in the project, then runs the loop below.

## State is shared, context is not (the core guarantee)

The three agents run as **isolated subagents** — each gets a fresh context and never sees
another agent's conversation. The orchestrator is the only component that holds context, and
it relays **pointers to files, never another agent's prose**. Concretely:

- Inter-agent information flows through `.harness/` files only (`spec.md`, `contract.md`,
  `findings.md`, trace logs).
- Every spawn prompt the orchestrator emits carries only: workspace path, which files to
  read/write, the agent's mode, and control signals (`ACCEPT`/`REJECT`/`PASS`/`FAIL`,
  sprint number). You can grep the spawn prompts and confirm none carries another agent's
  text.

That property — **shared state, isolated context** — is what the harness exists to enforce.

## Roles

1. **Planner** writes `spec.md` from the human request.
2. **Generator** writes `sprint_contract.md`, builds only that sprint, and logs evidence.
3. **Evaluator** attacks the result with Playwright, rubric checks, and trace review.

> Three agents. Zero shared context. Disk is the only shared memory.

## Why This Exists

Agents fail when they self-grade, keep everything in context, one-shot large work, or treat shallow tests as proof. This harness forces physical evidence:

- written intent
- written contract
- observable behavior
- reproducible checks
- adversarial findings
- prompt/rubric patches when judgment is wrong

## Package Layout

```txt
install.sh                       one-shot global installer (and --uninstall)
install/
  agents/                        harness-planner.md harness-generator.md harness-evaluator.md
  skills/agent-harness/SKILL.md  the orchestrator
agents/                          original role prompts (reference)
contracts/                       sprint_contract_template.md sprint_contract_example.md
rubrics/                         master_rubric.md design_rubric.md functionality_rubric.md security_rubric.md
templates/                       spec_template.md findings_template.md trace_review_template.md prompt_patch_template.md
docs/                            operating_loop.md file_protocol.md physics_first_principles.md
```

`install/` holds the files copied into `~/.claude` — the path-parameterized agents that read
exact paths from the orchestrator. The top-level `agents/`, `rubrics/`, `templates/`, and
`docs/` are the human-readable design source the install files are derived from.

The per-run disk bus the agents coordinate through lives in `<project>/.harness/` — see
[docs/file_protocol.md](docs/file_protocol.md) for the canonical layout.

## Loop

```txt
Human prompt
 -> Planner writes spec.md
 -> Generator drafts sprint_contract.md
 -> Evaluator rejects or accepts contract
 -> Generator builds exactly the accepted contract
 -> Evaluator clicks, breaks, inspects, scores
 -> Generator fixes only findings
 -> Repeat
```

## Non-Negotiables

- If it is not written to disk, it does not exist.
- If it was not clicked or measured, it was not verified.
- If the Generator grades itself, ignore the grade.
- If the contract is vague, reject before coding.
- If the UI looks like a default template, fail originality.
- If a feature is stubbed but presented as real, fail the sprint.
- If the user would need to guess, fail functionality.

## Anti-Overengineering Rule

Do not add ceremony unless it prevents a real failure. The only required files per sprint are:

- `spec.md`
- `sprint_contract.md`
- `generator_trace.log`
- `findings.md`
- relevant code/tests/artifacts
