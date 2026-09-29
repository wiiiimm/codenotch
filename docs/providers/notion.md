# Notion AI (macOS)

Enable **Notion AI** in **Settings → Accounts**, sign in to Notion in the
Codenotch window, then close that window. The session stays in Codenotch's
persistent WebKit store. Sign out clears that session and its saved readings.
No Notion integration token or browser-cookie export is needed.

Codenotch shows the rolling allowance and the monthly billing-period allowance
for Business and Enterprise workspaces. The rolling allowance is the main ring;
the monthly allowance uses the optional second ring. The workspace name appears
as the group heading in the usage tooltip. Free or Plus workspaces that return
`not_applicable` show an explanation instead of a zero-percent gauge.

By default, the first Business or Enterprise workspace (ordered by workspace
ID) is selected, falling back to the first workspace if none has that tier.
To choose another, enter its workspace ID in the Notion AI account row and
press **Save**. Dashed and undashed IDs are accepted. An unavailable explicit
ID reports an error; it never silently selects another workspace. Saving a
workspace change clears previous readings before refreshing. Multiple signed-in
accounts are rejected rather than mixing their workspaces.

## Data and limitations

This uses Notion's internal, session-authenticated web endpoints at
`https://app.notion.com`: `POST /api/v3/getSpaces`, followed by
`POST /api/v3/getCreditRateLimitStatus` with the selected `spaceId`.
These are unsupported endpoints and may change. This implementation follows the
response shapes documented by [CodexBar](https://github.com/steipete/CodexBar/blob/main/docs/notion.md)
and inspected in [Opscope's agent usage provider](https://github.com/stealth-factory/opscope/blob/main/widgets/src/widgets/agent-usage/notion.rs).

Each allowance uses the returned `used / limit`, preserving overage. Rolling
resets count from the reading time; monthly resets use `periodEndMs`. Monthly
pace uses the actual preceding calendar month in UTC. Missing clocks remain
absent, and missing windows are not fabricated. Preview enforcement is labelled
on the affected windows. Invalid numbers produce an error.

Custom Agent and Worker credit spending is **not** included. This change adds
the macOS provider; the Windows port is unchanged.

## Checks

- `make test` runs the Swift parser and provider-configuration tests with the
  app's existing test suite.
- `node Scripts/test-notion.mjs` tests the actual embedded request scripts with
  mocked responses, including workspace selection and authentication failures.
- A live acceptance check requires signing in to a Business or Enterprise
  workspace, comparing both allowances with Notion's usage page, then testing
  workspace switching and sign-out.
