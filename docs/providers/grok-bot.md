# Grok Bot (macOS)

Enable **Grok Bot** in **Settings → Accounts** to show a separate dial in the
main notch. Sign in to Cursor or cursor-agent on this Mac first. Codenotch
borrows the same Cursor session used by its Cursor provider; Grok Bot does not
require a separate browser sign-in or a Grok CLI login.

The dial reads `POST https://cursor.com/api/dashboard/get-sand-usage-status`
with an empty JSON object. It shows Grok Bot's own included or active trial
allowance. Cursor's monthly Auto/API readings and the existing Grok CLI dial
remain independent. Disabling Cursor's dial does not disable Grok Bot's dial.

Included usage uses the reported period start and reset timestamp. A trial
has no recurring reset: its expiry must not appear as a quota replenishment.
Exhausted allowances still show their reported usage. Accounts with no included
allowance or active trial show an explanation rather than an invented zero.

This is an internal Cursor dashboard endpoint and may change. The response
shape and trial rules were checked against CodexBar's
[CursorSandUsage](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorSandUsage.swift).
This change covers macOS only.

Run `make test` for the parser and mocked transport tests. For live acceptance,
compare the dial with the Grok Bot usage shown by Cursor, disable the Cursor
dial and verify Grok Bot still refreshes, then check behaviour on an account
without an allowance. No credentials are included in test fixtures.
