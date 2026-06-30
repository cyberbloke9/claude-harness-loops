# Sprint Contract Template

## Sprint ID

## Sprint Name

## Source Spec
Path: `spec.md`

## Objective
One paragraph. State the exact user-visible outcome. No hype.

## User Stories Covered

- As a [specific user], I can [specific action], so that [specific outcome].

## Explicit Non-Goals

- This sprint will not...

## Routes / Screens / Components Affected

| Surface | Change required | Out of scope |
|---|---|---|
| | | |

## Atomic Behaviors

### B-001: [behavior name]

- Starting state:
- User action:
- System response:
- State/data change:
- Success evidence:
- Failure evidence:

## Required States

- Empty:
- Loading:
- Success:
- Error:
- Invalid input:
- Permission denied/auth missing:
- Slow network/offline, if relevant:

## Interaction Requirements

- Hover:
- Focus:
- Active/pressed:
- Disabled:
- Submitted:
- Recovery after failure:

## Accessibility Requirements

- Keyboard path:
- Focus order:
- Visible focus indicator:
- Labels/names:
- Contrast:
- Screen reader expectations:

## Responsive Requirements

- Mobile width behavior:
- Tablet width behavior:
- Desktop width behavior:
- No-overlap/no-horizontal-scroll conditions:

## Design / Originality Requirements

- Visual hierarchy:
- Typography/spacing bar:
- Domain-specific copy/content:
- Forbidden generic patterns:
- What would count as “too templated”:

## Security / Privacy Assumptions

- Data stored:
- Data exposed:
- Auth/permission assumptions:
- Unsafe behavior explicitly forbidden:

## Verification Commands

```bash
# install/start/test/lint/build commands
```

## Required Evaluator Click Paths

1. Happy path:
2. Invalid path:
3. Empty state path:
4. Error/recovery path:
5. Keyboard-only path:
6. Mobile viewport path:

## Pass Criteria

The sprint passes only if:

1. Every atomic behavior is observable in the running app.
2. No required state is stubbed, blank, or misleading.
3. Main flow works through real clicks, not only tests.
4. Console/network output has no unexplained errors.
5. Design does not look like an unmodified template.
6. Evaluator evidence reproduces the claimed behavior.
