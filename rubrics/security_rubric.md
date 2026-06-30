# Security Rubric

Use this for any sprint touching auth, user data, payments, permissions, files, APIs, admin controls, or external integrations.

## Required Checks

- Auth boundaries are enforced server-side where relevant.
- Sensitive routes are protected.
- User input is validated.
- Error messages do not leak secrets.
- No API keys or secrets are committed.
- File uploads are constrained.
- Permissions are explicit.
- Destructive actions require confirmation.
- Logs avoid sensitive data.

## Immediate Fail Conditions

- Hardcoded credentials.
- Client-only authorization for sensitive actions.
- Fake auth presented as real auth.
- Exposed secret values.
- Insecure direct object reference risk.
- No validation for security-sensitive input.

## Evidence Required

Security claims must include:

- files inspected
- commands run
- tests performed
- threat assumptions
- remaining risks
