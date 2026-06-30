# Sprint Contract Example

## Sprint ID
SPRINT-001

## Sprint Name
Account sign-in flow

## Objective
Implement a real sign-in screen where a user can enter credentials, receive validation feedback, submit successfully against the configured auth mechanism, and land on the dashboard with authenticated state preserved after reload.

## User Stories Covered

- As a returning user, I can sign in so that I can access my dashboard.
- As a user who mistypes credentials, I can understand what went wrong and retry.
- As a keyboard user, I can complete sign-in without a mouse.

## Explicit Non-Goals

- No password reset flow.
- No social login.
- No account creation.

## User-Visible Behaviors

### Submit valid credentials

- Trigger: user enters valid email and password, then submits.
- Expected response: user is routed to `/dashboard`.
- Data affected: auth session is created.
- Edge cases: reload keeps user on authenticated route.

### Submit invalid credentials

- Trigger: user enters invalid credentials.
- Expected response: inline error appears and focus remains recoverable.
- Data affected: no session is created.
- Edge cases: password field is not cleared unless security requires it.

### Submit empty form

- Trigger: user submits without required fields.
- Expected response: field-level validation appears.

## Routes / Screens Affected

| Route / Screen | Expected State |
|---|---|
| `/login` | sign-in form |
| `/dashboard` | authenticated landing page |

## Data States

- Empty: form fields blank with clear labels.
- Loading: submit button shows pending state and prevents double submit.
- Success: dashboard loads.
- Error: credentials error appears.
- Invalid: field-level validation appears.

## Accessibility Requirements

- All inputs have labels.
- Tab order follows visual order.
- Error messages are announced or associated with fields.
- Submit button is reachable by keyboard.

## Responsive Requirements

- Mobile layout fits 375px width without horizontal scroll.
- Desktop layout does not stretch form beyond readable width.

## Design Quality Requirements

The form should look specific to this product, not like a default auth template. Typography, spacing, and error states must feel intentional.

## Verification Commands

```bash
npm test
npm run lint
npm run dev
```

## Required Evaluator Checks

- [ ] Open `/login`
- [ ] Submit empty form
- [ ] Submit invalid credentials
- [ ] Submit valid credentials
- [ ] Reload `/dashboard`
- [ ] Test keyboard-only flow
- [ ] Resize to mobile viewport
- [ ] Check console errors

## Pass Criteria

The sprint passes only if sign-in works through the UI, invalid states are clear, authenticated state survives reload, and the Evaluator records browser evidence.
