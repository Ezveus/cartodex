# MCP Token Expiry & Self-Serve Rotation — Design

**Date:** 2026-08-11
**Status:** Approved
**Issue:** #57
**Builds on:** `2026-07-01-collection-deck-mcp-design.md` (the MCP server and the per-user bearer token this feature now makes manageable from the app).

## Goal

The MCP bearer token (`users.api_token_digest`) is long-lived, grants full read/write access to a
user's collection and decks, and can only be rotated through the `mcp:token` rake task. Give it an
optional expiry enforced at authentication, and a self-serve page to generate, inspect and revoke it
— without ever letting the raw value reach persistent storage.

## Confirmed decisions (from the brainstorming interview)

1. **One token per user.** Keep `users.api_token_digest` and extend the `users` table. No
   `api_tokens` table, no named per-client tokens: the issue speaks of *the* token, and a single
   column keeps `authenticate_api_token` a one-shot indexed lookup.
2. **Expiry chosen at generation, defaulting to 90 days.** A select offers 30 days / 90 days /
   1 year / never. `api_token_expires_at` is nullable and `NULL` means *never expires*.
3. **`last_used_at` is tracked, with a throttled write.** Recorded at most once per hour per user so
   the MCP authentication path does not take a SQLite write on every request.
4. **A `/settings` page owns the UI**, with the MCP token as its first section, rather than a
   standalone token page or a dashboard widget. It gives future account settings a home and matches
   the issue's wording.
5. **`create` renders instead of redirecting** — see [Showing the raw token once](#showing-the-raw-token-once).

## Data model

Three nullable columns on `users`; no new table.

| Column | Meaning |
| --- | --- |
| `api_token_expires_at` | When the token stops authenticating. `NULL` = never expires. |
| `api_token_created_at` | When the current token was generated. |
| `api_token_last_used_at` | Last successful authentication, to the hour (see the throttle below). |

Tokens that predate this change inherit `NULL` in all three: they keep working (no expiry) and
render with `—` as their creation date. No backfill is possible — the information does not exist.

**`api_token_digest` carries a unique index.** Revoking sets it to `NULL`, and several users may be
revoked at once. That is valid: SQL treats `NULL`s as distinct within a unique index, in SQLite as in
PostgreSQL, so it survives the migration contemplated in #62.

### Lifetimes

A `User::TOKEN_LIFETIMES` constant maps a form value to a duration, `nil` meaning *never*:

```ruby
TOKEN_LIFETIMES = { "30d" => 30.days, "90d" => 90.days, "1y" => 1.year, "never" => nil }.freeze
DEFAULT_LIFETIME_KEY = "90d"
```

This constant is the **single** definition of the default: `regenerate_api_token`'s keyword defaults
to `TOKEN_LIFETIMES.fetch(DEFAULT_LIFETIME_KEY)` rather than repeating a literal `90.days`, so the
model and the form can never disagree about what "default" means.

The duration reaches the server from a form, so it is untrusted input: the controller resolves it
through this constant and falls back to `DEFAULT_LIFETIME_KEY` when the key is missing or unknown,
rather than honouring an arbitrary value or raising.

## Model & authentication

`regenerate_api_token(expires_in: 90.days)` now takes a duration (`nil` for never). It stamps
`api_token_created_at`, computes `api_token_expires_at`, and resets `api_token_last_used_at` to
`NULL`. The `mcp:token` rake task keeps its current behaviour through the default, and may accept an
optional lifetime as a second argument.

`revoke_api_token!` sets `api_token_digest` and the three columns above back to `NULL`, leaving the
user with no token at all rather than an unusable one.

`authenticate_api_token` gains two steps, in this order:

```ruby
user = find_by(api_token_digest: digest_api_token(raw))
return if user.nil?
return if user.api_token_expired?   # expires_at present && past
user.touch_api_token_usage          # throttled
user
```

The expiry check comes **before** the usage stamp: an expired token must leave no trace of use.
Nothing changes at the MCP endpoint — an expired token falls through to the existing
`head :unauthorized`, and the response does not distinguish *expired* from *invalid*.

`touch_api_token_usage` performs a single `update_column`, and only when the stored value is older
than one hour. On the hot path that caps the cost at one write per hour per user, with no validations
and no callbacks, so it never interacts with `ApplicationService#serialized_transaction`.

## Routes & controllers

Inside the existing `authenticate :user` block:

```ruby
resource :settings,  only: [ :show ]
resource :mcp_token, only: [ :create, :destroy ]
```

- `SettingsController#show` renders the page.
- `McpTokensController#create` resolves the requested lifetime, generates (or rotates) the token, and
  responds with a Turbo Stream that replaces the token section, carrying the raw value.
- `McpTokensController#destroy` revokes and redirects to `/settings` with a notice. Revoking when no
  token exists is idempotent: same notice, no error.

Both controllers stay thin, delegating to the `User` methods above — no token logic in controllers.

## Showing the raw token once

The obvious implementation of a one-shot reveal is `flash[:token]`, and it is wrong: the Rails flash
is serialised into the **session cookie**, so the raw token would be written to the browser's disk in
clear text and sent back on the next request — defeating the point of storing only a digest.

Instead `create` **renders** the fresh token into the response body and nowhere else. No cookie, no
round-trip, and refreshing the page makes it disappear, which is exactly the intended
"shown once" behaviour.

This has a consequence worth stating, because it is easy to trip over: **Turbo Drive does not render
a 200 HTML response to a form submission** — it expects a redirect, and only renders a direct
response for 4xx/5xx. A plain `render` would therefore display nothing. The fix is to answer with a
Turbo Stream that replaces the token section, which is idiomatic here (the repo already streams
import progress) and forces the section into its own component with a DOM id — better structure, and
testable in isolation. `data: { turbo: false }` on the form is the lazier alternative: it works via a
full page load, but costs the same view work without the benefit.

## Views (Phlex)

- **`Settings::ShowView`** — page shell; renders the section.
- **`Settings::McpTokenSection.new(user:, raw_token: nil)`** — the replaceable unit, `id: "mcp-token"`:
  - when `raw_token` is present, the one-shot reveal: the value in monospace, a "copy it now, it will
    not be shown again" warning, a copy button backed by a small Stimulus controller, and the
    ready-to-paste client config snippet (endpoint plus the `Authorization: Bearer …` header);
  - metadata: created / expires (relative — "in 89 days" — with a distinct **expired** state) / last used;
  - the generation form with the expiry select (30 days / 90 days / 1 year / never, defaulting to 90 days);
  - the revoke button, rendered only when a token exists, with a confirmation.

The label reads **Generate** with no token and **Rotate** when one exists — including an expired one,
which still exists and still shows its metadata, flagged as expired. Rotating warns that the existing
token stops working immediately.

Because the usage stamp is throttled, "last used" can lag reality by up to an hour. That is expected
and the copy should not imply second-level precision.

A `Settings` entry joins the navbar's `right_section` in `Ui::AppNavbar`, alongside Admin and
Sign out. Existing `Ui::*` components are reused; any genuinely new primitive gets registered in
`/styleguide`, per the repo convention.

## Testing

**Model.** An expired token is rejected at authentication; a valid one is accepted; revocation breaks
authentication; `regenerate_api_token` resets `last_used_at`; and the throttle holds — two
authentications within the hour produce one write, a third after the hour produces a second.

**Controller.** The settings page renders; `create` returns a Turbo Stream containing the raw token;
`destroy` revokes; an unknown or missing lifetime falls back to 90 days; unauthenticated access
redirects.

**The test that locks the design in:** the raw token must appear in **no** `Set-Cookie` header —
neither in the `create` response nor on the following `GET`. This is what stops someone from later
"simplifying" the reveal back through the flash.

## Out of scope

- Multiple named tokens per user (decision 1). If per-client revocation is ever wanted, that is a
  separate `api_tokens` table and its own design.
- Scoping a token to a subset of MCP tools (read-only tokens).
- Notifying the user before a token expires.
- Rate-limiting or auditing token generation itself; the MCP endpoint's existing per-IP throttle is
  unchanged by this work.
