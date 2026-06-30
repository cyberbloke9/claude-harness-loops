# Functionality Rubric

Functionality means real user task completion under realistic conditions.

## Required Checks

For every user flow, test:

- first load
- navigation
- successful completion
- invalid input
- empty data
- loading state
- error state
- reload behavior
- back/forward behavior
- mobile viewport
- keyboard operation

## Pass Standard

A feature passes only if:

1. The user can discover what to do.
2. The user can complete the task without hidden knowledge.
3. Errors explain what happened and how to recover.
4. State is preserved or reset intentionally.
5. No console errors appear during normal usage.

## Common Failures

- Buttons that do nothing.
- Forms without validation.
- Fake success messages.
- Navigation that changes URL but not state.
- Data that disappears unexpectedly.
- Disabled states with no explanation.
- Broken keyboard flow.
- Mobile layout hiding essential controls.
