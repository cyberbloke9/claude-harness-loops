# Physics First Principles for Agent Harnesses

This file exists to keep the harness grounded. Do not turn it into philosophy. Use it to make pass/fail decisions sharper.

## 1. State Must Be Physical

Context is volatile. Files are durable.

If a requirement, decision, test, or risk is not on disk, it is not part of the system.

Required durable state:

- `spec.md`
- `sprint_contract.md`
- `generator_trace.log`
- `findings.md`
- artifacts: screenshots, traces, command output, source code

## 2. Split Forces

A single agent asked to plan, build, and judge will protect its own work.

Separate forces:

- Planner compresses intent.
- Generator applies construction.
- Evaluator applies destructive testing.

The system improves because these forces collide through files.

## 3. Entropy Is Default

Long context causes drift: forgotten constraints, shallow tests, fake certainty, premature wrap-up.

Counter with:

- small sprint contracts
- atomic pass criteria
- external traces
- hard evaluator gates
- prompt patches after repeated failures

## 4. Evidence Has Weight

Evidence hierarchy, strongest first:

1. Reproducible user click path with trace/screenshot.
2. Automated browser test reproducing behavior.
3. Command output from build/test/lint.
4. Source inspection tied to a specific behavior.
5. Agent claim.

Agent claim alone has near-zero weight.

## 5. Subjective Quality Must Be Debroken

“Good design” is too vague. Break it into observable parts:

- first-screen clarity
- hierarchy
- spacing rhythm
- contrast
- typography scale
- responsive behavior
- empty/error/loading states
- copy specificity
- avoidance of unmodified defaults

## 6. Contracts Are Impact Surfaces

A contract converts intent into collision points the Evaluator can strike.

Bad: “Build auth.”

Good: “A new user can create an account, see field-level validation, sign in, sign out, reload, and remain signed out; no fake auth state; keyboard-only path works.”

## 7. Harshness Prevents Slop

A friendly evaluator creates false positives. The Evaluator should search for:

- stubs
- dead controls
- fake data
- generic copy
- inaccessible flows
- broken mobile states
- unsupported claims
- missing traces

## 8. Traces Debug the Harness

When the output disappoints, inspect traces before blaming only code.

Patch:

- planner prompt if intent was lost
- contract template if behavior was vague
- generator prompt if it overclaimed or stubbed
- evaluator prompt/rubric if slop passed

## 9. Delete Scaffolding Later

Keep the harness small. Delete any file, role, or ritual that no longer catches real failures.
