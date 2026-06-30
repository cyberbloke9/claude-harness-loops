# Master Evaluation Rubric

Use this for every sprint unless the contract explicitly overrides weights.

## Scoring Scale

- **0**: absent, fake, unreachable, or broken.
- **1**: token attempt; mostly unusable or generic.
- **2**: partial; happy path may work but real use breaks.
- **3**: baseline acceptable; not embarrassing, but weak.
- **4**: strong; reliable, clear, and hard to break.
- **5**: excellent; distinctive, resilient, and unusually polished.

Passing threshold:

- no blocker findings
- no high-severity unresolved findings
- functionality >= 4
- evidence/process >= 4
- weighted total >= 4

## 1. Design Quality

Question: Does the product feel intentionally composed?

Fail or reduce score for:

- unclear first screen
- weak hierarchy
- random spacing
- clutter without priority
- low contrast
- mismatched components
- empty states that feel abandoned
- “generic SaaS dashboard” energy

High score requires:

- clear visual priority
- domain-aware layout
- useful empty/error states
- coherent component language
- restrained but intentional detail

## 2. Originality

Question: Are there custom product decisions, or just defaults?

Fail or reduce score for:

- stock cards, stock hero, stock purple gradient
- placeholder labels
- copy that could describe any app
- component-library defaults with no product taste
- generic “AI-powered productivity” language

High score requires:

- domain-specific copy
- custom interaction choices
- visual decisions tied to user intent
- details that could not be pasted into any random app

## 3. Craft

Question: Is execution careful at the pixel and state level?

Fail or reduce score for:

- misalignment
- inconsistent spacing rhythm
- poor typography scale
- layout jank
- overflow at common widths
- weak focus states
- unhandled hover/disabled/submitted states
- console warnings from careless implementation

High score requires:

- responsive polish
- consistent state treatment
- readable type hierarchy
- clean transitions without distraction
- no visible rough edges in main flows

## 4. Functionality

Question: Can users complete the task without guessing?

Fail or reduce score for:

- dead buttons
- fake data presented as real
- no recovery from errors
- validation that appears too late or not at all
- routing dead ends
- state lost unexpectedly
- success messages without actual effects

High score requires:

- happy path works
- invalid path is specific and recoverable
- empty/loading/error states work
- persistence works when required
- navigation is obvious
- user always knows what happened

## 5. Evidence and Process

Question: Is the pass based on observation?

Fail or reduce score for:

- claims without logs
- curl-only evidence for UI behavior
- no screenshots/traces for visual work
- missing console inspection
- no record of commands
- self-certification language
- skipped failed checks

High score requires:

- reproducible commands
- Playwright/manual click evidence
- screenshots where visual quality matters
- console/network inspection
- trace logs with risks disclosed
- regression checks for fixed findings

## Immediate Fail Conditions

Fail the sprint immediately if:

- contract was not accepted before implementation
- main user flow cannot complete
- required behavior is stubbed/faked
- app cannot start
- Evaluator cannot inspect the app
- severe accessibility blocker blocks main flow
- user data/auth/money/permissions are handled unsafely
- Generator expanded scope without contract revision
- Generator claims production readiness without evidence
