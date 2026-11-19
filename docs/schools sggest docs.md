# School suggestions endpoint

`GET /api/v1/schools/suggest?q=<text>` (alias: `query`) — public autocomplete used by parent onboarding.

- Fewer than 2 characters (or blank/missing): `200 { success: true, schools: [] }` (not a 400, the user is still typing).
- Case-insensitive match on `schoolName`; prefix matches first, then contains matches; alphabetical within each group; max 10.
- Only schools with status `active` (or no status).
- User input is passed through `Regexp.escape`.
- Returns only public fields: `id`, `schoolName`, `city`, `province`, `logo`. Never emails, owner ids, balances, admins or invites.
- Unexpected errors: `500 { success: false, message }` with no backtrace.

`GET /api/v1/schools/search?query=<name>` is unchanged: it is the school-name availability check used when creating a school (`{ isAvailable }`), and it still returns 400 without `query`.

## Root cause of the original bug
Onboarding called `/schools/search?q=...`. That route reads `query` and only answers "is this name taken", so it returned 400 and never a list.

## Out of scope, noted
`GET /api/v1/schools` (`schools#index`) returns every field of every school to any caller.