# MCP OAuth Authorization — Design

**Date:** 2026-08-14
**Status:** Approved
**Builds on:** `2026-07-01-collection-deck-mcp-design.md` (the MCP server itself) and
`2026-08-11-mcp-token-management-design.md` (the per-user bearer token this feature is designed to
eventually replace).

## Goal

Cartodex's MCP endpoint authenticates with a static per-user bearer token supplied in an
`Authorization` header. Claude Code accepts that (`claude mcp add --transport http … --header
"Authorization: Bearer <token>"`), but **Claude's web custom-connector dialog does not**: it offers
only a server URL plus optional OAuth client ID and secret. Cartodex is therefore unusable as a web
connector today.

Make Cartodex an OAuth 2.1 authorization server and OAuth-protected resource, so that any user —
not only the app's owner — can connect their own Claude account by clicking through a consent
screen, with no token to copy and no secret to handle.

## Confirmed decisions (from the brainstorming interview)

1. **Multi-user from the start.** The feature targets other Cartodex users connecting their own
   Claude accounts, not just the owner. Devise is `:registerable`, so per-user consent is meaningful.
2. **Dynamic Client Registration, not a pre-registered client.** Claude supports both, but the
   pre-registered path would require publishing a `client_id`/`client_secret` pair to every user,
   which defeats the secret. See [Dynamic client registration](#dynamic-client-registration).
3. **Coexistence, then deprecation.** The static bearer token keeps working alongside OAuth. It is
   marked deprecated in `/settings` and the docs once OAuth is verified against a real connector,
   and removed in a separate later change.
4. **Two scopes, `mcp:read` and `mcp:write`,** with the consent screen able to grant read without
   write. See [Scopes](#scopes).
5. **Doorkeeper 5.9.6 as the authorization server**, with the MCP-specific pieces written here. See
   [Why Doorkeeper 5.9, not 6.0.0.beta](#why-doorkeeper-59-not-600beta).
6. **A redirect-URI host allowlist on dynamic registration**, rather than accepting any HTTPS URI.

## What the MCP specification requires

From the [MCP authorization
specification](https://modelcontextprotocol.io/specification/draft/basic/authorization), the
obligations that fall on us:

| Requirement | Where it lands |
| --- | --- |
| MCP server **MUST** implement OAuth 2.0 Protected Resource Metadata (RFC 9728) | `Oauth::MetadataController#protected_resource` |
| Authorization server **MUST** provide RFC 8414 or OpenID Connect Discovery | `Oauth::MetadataController#authorization_server` |
| 401 **MUST** carry `WWW-Authenticate` pointing at the resource metadata | `Mcp::ServerController` |
| Authorization server **MUST** implement OAuth 2.1 (PKCE mandatory, no implicit/password grants) | Doorkeeper config |
| Server **MUST** validate the token was issued for it as audience (RFC 8707) | [Audience validation](#audience-validation) |
| Dynamic Client Registration (RFC 7591) | `MAY` — we implement it because Claude relies on it |

The draft specification marks DCR as **deprecated** in favour of OAuth Client ID Metadata Documents,
where the client presents an HTTPS URL as its `client_id`. Claude uses DCR today, so DCR is what we
build. This is recorded as known debt in [Future direction](#future-direction), not presented as a
durable choice.

## Why Doorkeeper 5.9, not 6.0.0.beta

Doorkeeper 6.0.0.beta2 (released 2026-08-10) already ships RFC 8414 metadata (`issuer`,
`custom_metadata`) and RFC 8707 resource indicators (`resource_indicator_validator`). Doorkeeper
5.9.6 has neither, but has had `force_pkce` since 5.7.1.

We take 5.9.6 anyway. The two features the beta would hand us are the *easiest* parts of the delta —
a near-static JSON document and a parameter comparison. The hard parts (dynamic registration, RFC
9728 metadata, a scope-narrowing consent screen) are ours either way, in both versions. Betting the
security core of a publicly reachable authorization server on a four-day-old beta of a major version
to save roughly a hundred lines is the wrong trade. Migrating to 6.0 is a deliberate later change.

## Architecture

### Doorkeeper configuration

| Option | Value | Why |
| --- | --- | --- |
| `grant_flows` | `["authorization_code"]` | No implicit, password or client-credentials grant. |
| `force_pkce` | enabled | Required by OAuth 2.1. Doorkeeper 5.9 exempts **confidential** clients from this, which is every client Claude registers by DCR, so the exemption is removed by a small `Doorkeeper::OAuth::PreAuthorization` prepend — see [PKCE is not free here](#pkce-is-not-free-here). |
| `pkce_code_challenge_methods` | `%w[S256]` | Doorkeeper defaults to `%w[plain S256]`, and its token endpoint honours `plain`. A `plain` challenge is transmitted openly in the authorization request and *is* the verifier, so it gives no protection against the code-interception attack PKCE exists to prevent. Restricting it is what makes the metadata document's `code_challenge_methods_supported: ["S256"]` a true statement rather than a claim. |
| `use_refresh_token` | `true` | Lets Claude refresh silently instead of re-prompting. |
| `hash_token_secrets` | enabled | Matches the choice already made for `api_token_digest`. |
| `hash_application_secrets` | enabled | Same. |
| `default_scopes` | `["mcp:read"]` | What a client gets when it requests no scope at all. |
| `optional_scopes` | `["mcp:write"]` | Grantable, and refusable at consent. |
| `enforce_configured_scopes` | enabled | Added during Task 4. Disabled by default; without it, `Oauth::ClientRegistrar::SERVER_SCOPES` was the *only* thing standing between a registration request and an application holding a scope this server never configured, unlike `redirect_uri`, which already had two independent layers. |
| `access_token_expires_in` | `2.hours` | Not in the original design; needed a value and this is Doorkeeper's own default made explicit. |
| `skip_authorization` | `false` | Every user consents explicitly, every time a new client asks. |
| `resource_owner_authenticator` | Devise `current_user`, else redirect to sign-in with return | |
| `force_ssl_in_redirect_uri` | `->(uri) { !ClientRegistrar::PLAIN_HTTP_HOSTS.include?(uri.host) }` | Added during Task 4. Doorkeeper's `RedirectUriValidator` forces HTTPS on every redirect URI outside development with no loopback exception, so without this override the model layer would reject a loopback CLI client's `http://` redirect before `Oauth::ClientRegistrar`'s own checks ever ran. Points at `ClientRegistrar`'s own host list rather than restating it. |

Three tables land in the `primary` database and therefore in `db/schema.rb`:
`oauth_applications`, `oauth_access_grants`, `oauth_access_tokens`.

### PKCE is not free here

Both of these were found during implementation, not design, and both are the difference between PKCE
working and PKCE being decorative. Neither is obvious from Doorkeeper's configuration surface.

**`force_pkce` exempts confidential clients.** `Doorkeeper::OAuth::PreAuthorization#validate_code_challenge`
reads `return true if client.confidential` before it checks for a challenge (5.9.6,
`pre_authorization.rb:150`). Clients registered through DCR with a `client_secret` — which is what
Claude registers — are confidential, so `force_pkce` alone would leave PKCE optional for precisely
the client this feature exists to serve. The exemption is removed by prepending a module that
reproduces the method without that line, still gated on `force_pkce?`. The guard against a future
Doorkeeper upgrade silently restoring the exemption is a test that authorizes a **confidential**
application without a challenge and asserts the redirect carries `error=invalid_request`; a public
application would pass either way and prove nothing.

**`plain` is accepted by default.** `pkce_code_challenge_methods` defaults to `%w[plain S256]`
(`config.rb:276`) and `AuthorizationCodeRequest` has a live plaintext branch
(`authorization_code_request.rb:101`). With `plain`, the challenge sent openly in the authorization
request *is* the verifier, so an attacker who intercepts the authorization code already holds
everything needed to redeem it.

Both tests assert on the **redirect's query string**, not on the HTTP status. A rejected authorization
request redirects to the client's registered `redirect_uri` carrying `error=`, exactly as an accepted
one redirects carrying `code=` — both are 302, so a status assertion cannot tell them apart.

### Routes

All of these sit **outside** the `authenticate :user` block in `config/routes.rb`. Doorkeeper handles
its own sign-in redirect through `resource_owner_authenticator`, and the metadata documents must be
publicly readable.

```ruby
use_doorkeeper do
  controllers authorizations: "oauth/authorizations", tokens: "oauth/tokens"
  skip_controllers :applications, :authorized_applications
end

post "oauth/register", to: "oauth/registrations#create"
get ".well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
get ".well-known/oauth-protected-resource",     to: "oauth/metadata#protected_resource"
get ".well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"
```

The `controllers` line is not in the original design's sketch of this block. It is what actually
routes Doorkeeper's `/oauth/authorize` and `/oauth/token` to `Oauth::AuthorizationsController` and
`Oauth::TokensController` instead of the gem's own — without it, the consent-narrowing and resource-
indicator code added at Tasks 6 and 7 would sit in the app unreached.

The protected-resource document is served at **two** paths deliberately. RFC 9728 has the client
insert the well-known segment *before* the resource's path, so the canonical URL for a resource at
`https://cartodex.ezveus.eu/mcp` is `/.well-known/oauth-protected-resource/mcp`. Real clients are
inconsistent about this, and serving both costs one route.

`skip_controllers :applications, :authorized_applications` keeps Doorkeeper's ERB admin views out of
the app: client management happens through DCR, and the "connected applications" list is a Phlex
component of ours (see [Settings](#settings)).

### New files

| Path | Responsibility |
| --- | --- |
| `app/controllers/oauth/registrations_controller.rb` | RFC 7591 endpoint; delegates to the service |
| `app/controllers/oauth/metadata_controller.rb` | The two `.well-known` documents |
| `app/controllers/oauth/authorizations_controller.rb` | Subclasses Doorkeeper's; narrows scopes at consent |
| `app/controllers/oauth/tokens_controller.rb` | Subclasses Doorkeeper's; adds RFC 8707 resource validation (not in the original design; see [Audience validation](#audience-validation)) |
| `app/controllers/concerns/oauth/resource_indicator_enforcement.rb` | Shared `before_action` for the resource check, included by both the authorizations and tokens controllers above (not in the original design) |
| `app/services/oauth/client_registrar.rb` | Validates registration metadata, creates the application |
| `app/services/oauth/resource_indicator.rb` | The single definition of the canonical resource URI and RFC 8707 comparison; used by the metadata controller and both endpoints above (not in the original design — the design described the check inline on the two controllers) |
| `app/views/components/oauth/consent_view.rb` | Phlex consent screen |
| `app/views/components/settings/connected_apps_section.rb` | Connected applications + revocation |
| `app/jobs/oauth/purge_stale_applications_job.rb` | Deletes never-authorized registrations older than the grace period (not in the original design's file list, though the job itself was — see [Purge](#purge)) |

## Connection flow

The user pastes `https://cartodex.ezveus.eu/mcp` into Claude's connector dialog and leaves the
advanced fields empty. Then:

1. Claude calls `/mcp` with no token and receives **401** with
   `WWW-Authenticate: Bearer resource_metadata="https://cartodex.ezveus.eu/.well-known/oauth-protected-resource/mcp"`.
2. Claude reads the protected-resource document and finds `authorization_servers`.
3. Claude reads `/.well-known/oauth-authorization-server` and learns the authorize, token and
   revocation endpoints.
4. Claude registers itself at `POST /oauth/register` and receives a `client_id` and `client_secret`.
5. Claude opens the user's browser at `/oauth/authorize` with PKCE parameters and a `resource`
   parameter.
6. The user signs in to Cartodex if needed, sees the consent screen, and approves.
7. Claude exchanges the authorization code plus `code_verifier` for an access token and a refresh
   token, and calls `/mcp` with the access token.

No secret is ever handled by the user.

## Dynamic client registration

`POST /oauth/register` is unauthenticated by necessity — the client has no credentials yet. Three
guardrails compensate.

### Redirect-URI host allowlist

This is the security decision of the feature. With unrestricted registration, anyone can register a
client pointing at their own server, name it `Claude`, and phish a Cartodex user into authorizing
it — the attacker then holds a token over that user's collection and decks. The client name comes
from the registration request and is entirely attacker-controlled.

```ruby
Oauth::ClientRegistrar::ALLOWED_REDIRECT_HOSTS = %w[claude.ai claude.com localhost 127.0.0.1].freeze
Oauth::ClientRegistrar::PLAIN_HTTP_HOSTS       = %w[localhost 127.0.0.1].freeze
```

`claude.ai` is Claude's current callback host and `claude.com` is the announced successor; Anthropic
explicitly asks server operators to allowlist both. `localhost` and `127.0.0.1` cover CLI clients,
which use an ephemeral loopback callback port, and are the only hosts allowed over plain HTTP.
Anything else is rejected with `invalid_redirect_uri`. Supporting a new MCP client is a one-line
change plus a deploy — an acceptable price for closing the phishing vector almost entirely.

Two constants, not one, because the allowlist and the TLS exception answer different questions and
have different memberships in principle: `ALLOWED_REDIRECT_HOSTS` says which hosts may register at
all, `PLAIN_HTTP_HOSTS` says which of those may do so without HTTPS. Today the loopback pair happens
to be exactly the subset of the allowlist that gets the plain-HTTP exception, but a future host could
join the allowlist without joining the TLS exception — a self-hosted MCP client on a real domain would
belong in the first list only. `config/initializers/doorkeeper.rb`'s `force_ssl_in_redirect_uri`
callable reads `PLAIN_HTTP_HOSTS` specifically, not the combined allowlist, which is the mechanism this
split exists to support.

### Throttling

`/oauth/register` gets its own per-IP limiter, reusing `Mcp::ServerController::RATE_LIMIT_STORE`'s
call-time-`Rails.cache` pattern. Keying by IP is correct here: no user is known yet.

### Purge

Registration is open, so scanners will create `oauth_applications` rows indefinitely. A recurring job
deletes applications that have neither an access grant nor an access token after a few days.

### Accepted metadata

`token_endpoint_auth_method` may be `client_secret_post`, `client_secret_basic`, or `none` (a public
client relying on PKCE, stored as a non-confidential Doorkeeper application). The response is RFC
7591-shaped: `client_id`, `client_secret`, `client_id_issued_at`, `client_secret_expires_at: 0`, and
an echo of the accepted metadata. Errors are `invalid_redirect_uri` or `invalid_client_metadata`.

## Consent screen

A Phlex component overriding Doorkeeper's view, with `skip_authorization` left at `false`.

It shows the client's declared name **and the host of its redirect URI**. The name is self-declared
and therefore worthless as an identity claim; the redirect host is the part a user can actually
judge. Both are rendered as untrusted text.

Below them, the requested scopes appear as checkboxes in plain language. `mcp:read` is rendered but
not refusable — a connector without it can do nothing, so offering to remove it would only produce a
dead client. `mcp:write` can be unchecked, producing a working read-only connector.

Note that Doorkeeper's `default_scopes` only apply when a client requests no scope at all; it is the
consent controller below, not that setting, that guarantees `mcp:read` survives every authorization.

Doorkeeper cannot narrow scopes at consent on its own. `Oauth::AuthorizationsController` subclasses
`Doorkeeper::AuthorizationsController` and rewrites `params[:scope]` from the checkbox parameters
before calling `super`. This is the real implementation cost of the two-scope decision, and it is
what makes that decision worth anything.

## Audience validation

Doorkeeper 5.9.6 ignores the `resource` parameter. Cartodex exposes exactly one protected resource,
so a `before_action` on the authorize and token endpoints is sufficient: when `resource` is present,
it must equal the canonical URI `https://cartodex.ezveus.eu/mcp`, compared per RFC 8707 (scheme and
host case-insensitive, fragments rejected). A mismatch returns `invalid_target`.

`resource` is validated when present but **not required**. The specification obliges clients to send
it; refusing clients that do not would cost interoperability and buy nothing, since we have no second
resource a token could be misdirected to.

Audience validation at `/mcp` is then trivially satisfied: every token we issue targets the only
resource we have. **This reasoning stops holding the moment a second protected resource exists** —
at that point tokens must record their intended resource and `/mcp` must check it.

## Authentication on `/mcp`

`identify_token_user` tries a `Doorkeeper::AccessToken` first (`Doorkeeper::AccessToken.by_token`,
gated on `#accessible?`), then falls back to the existing static token, with the fallback branch
marked deprecated. One entry point, two identity sources, `@current_user` unchanged for the rest of
the controller. It never halts the callback chain itself — see [Rate limiting](#rate-limiting) for why
that split (`identify_token_user` / `reject_unauthenticated!`) exists and is load-bearing, not the
single `authenticate_token!` this section originally sketched.

### Refresh-token rotation

`use_refresh_token` alone is not rotation. Doorkeeper rotates **lazily**: redeeming a refresh token
mints a new access token carrying `previous_refresh_token`, and the superseded refresh token is only
revoked once the *new* access token is presented to a resource server. That hook,
`AccessToken#revoke_previous_refresh_token!`, has exactly one call site in the gem —
`Doorkeeper::OAuth::Token.authenticate` (`lib/doorkeeper/oauth/token.rb:19`), on the
`doorkeeper_authorize!` path. `Mcp::ServerController` resolves tokens itself and therefore bypasses
it, so it must fire the hook itself (`rotate_refresh_token`). Without that call, every refresh token
ever issued stays redeemable indefinitely and a replay is indistinguishable from a legitimate
refresh — a leaked refresh token would be a permanent, full-scope credential.

Firing it at `/mcp` rather than at the token endpoint is deliberate: it preserves Doorkeeper's
concurrency grace window, where two refreshes racing each other both succeed because the old token
survives until the new one is actually used.

**There is no `refresh_token_expires_in` in Doorkeeper 5.9.6** — the option does not exist in the
gem (`grep` over `lib/` returns nothing), and `RefreshTokenRequest` has no notion of a refresh-token
lifetime at all: validity is "the row is not revoked". Giving refresh tokens a TTL would mean a
custom column plus a patched `RefreshTokenRequest` validation, i.e. reimplementing a feature 6.0
does not have either. The bound on a refresh token's life is therefore rotation (above) plus user
revocation from `/settings`, and this is the reason [Settings](#settings) lists connections by
`revoked_at`, not by `#accessible?`.

## Scopes

Each tool class declares a `required_scope`: `mcp:read` by default, `mcp:write` for the six write
tools (`add_card_to_collection`, `set_collection_quantity`, `add_card_to_deck`,
`set_deck_card_owned_copies`, `reallocate_owned_copies`, `set_deck_card_quantity`).

Enforcement is a single filter, not the doubled check originally planned here. `McpTool.permitted_for`
filters the tool array by `@current_scopes` once, before `MCP::Server.new` is even called
(`Mcp::ServerController#handle`), and that one filtered array is both what `tools/list` advertises
and what `tools/call` dispatches from — verified directly in mcp-1.1.0: `MCP::Server#initialize` builds
`@tools` from exactly the array it is given (`server.rb:174`), and `call_tool` looks a tool up in that
same hash (`server.rb:754`) and raises "Tool not found" if it is absent (`server.rb:758`). A second
explicit scope check
inside `McpTool` would therefore be redundant, not defense in depth — there is nothing downstream of
the filter left to enforce against. A client that guesses an out-of-scope tool's name gets "tool not
found," the same outcome originally described as coming from a re-check that does not exist in the
shipped code.

### Deviation: no HTTP 403 `insufficient_scope`

The specification's step-up flow expects a `403` with `WWW-Authenticate: Bearer
error="insufficient_scope"`. We do not emit it. Producing it would mean parsing the JSON-RPC body in
the controller before handing the request to the transport, duplicating the method dispatch the `mcp`
gem owns.

The step-up flow exists so a client can discover a missing scope at call time. Under our design the
client discovers it at `tools/list` time instead — the same information, earlier. This is a
deliberate deviation from the letter of the specification.

Consequently the `WWW-Authenticate` challenge carries **no** `scope` parameter, and the
protected-resource document advertises `scopes_supported: ["mcp:read", "mcp:write"]`. The
specification covers this case explicitly: with no `scope` in the challenge, a client requests
everything advertised, and the consent screen arbitrates.

## Error handling

The `/mcp` 401 is identical whether the token is absent, expired, revoked or never existed — none of
those states may be distinguishable from outside.

| Situation | Response | Client behaviour |
| --- | --- | --- |
| No or invalid token on `/mcp` | 401 + `WWW-Authenticate` | Starts the authorization flow |
| Expired access token | 401 | Refreshes silently |
| Revoked client at the token endpoint | 401 `invalid_client` (Doorkeeper native) | Re-registers |
| Disallowed redirect host at registration | 400 `invalid_redirect_uri` | — |
| Malformed registration metadata | 400 `invalid_client_metadata` | — |
| `resource` mismatch | 400 `invalid_target` | — |
| Metadata endpoints | Always 200, public, cacheable JSON | — |

## Rate limiting

`/mcp` ends up with a per-IP limiter that counts **only requests that fail authentication**, and a
per-user limiter that carries the real quota. This shape is introduced by the separate
`fix/mcp-rate-limit-per-user` change and is a prerequisite for this one.

The `unless:` condition is not a detail. Two independent limiters both run as `before_action`s on
every request, so an authenticated request would increment both and its effective budget would be the
*smaller* of the two — the per-IP ceiling would keep binding and the per-user quota would be
unreachable from a fixed address. Scoping the IP limiter to unauthenticated traffic is what makes the
per-user quota real:

```ruby
before_action :identify_token_user            # sets @current_user, never halts
rate_limit to: 30, within: 1.minute, name: "mcp-ip", unless: -> { @current_user }, …
before_action :reject_unauthenticated!
rate_limit to: 300, within: 1.minute, by: -> { @current_user.id }, name: "mcp-user", …
```

The per-user limiter covers **both** authentication paths without modification, since it keys on
`@current_user.id`.

This matters more under OAuth than it did before. Claude web connectors call from Anthropic's shared,
rotating egress IPs: with a per-IP ceiling applying to authenticated traffic, unrelated users would
throttle each other. Only unauthenticated requests now land in the IP bucket — each new connector's
initial 401 probe, and expired tokens between refreshes — which is sparse enough for 30/min to hold.

The tradeoff, stated so it is not rediscovered later: the token lookup now happens *before* the
throttle. A request past the IP ceiling used to be refused with no database work; now every attempt
costs an indexed digest lookup before it is counted. The limiter still caps invalid-token spam, but
it protects the application rather than the database.

## Settings

Skipping Doorkeeper's `:authorized_applications` controller means building its counterpart in Phlex:
the user's connected applications, with granted scopes, connection date, and a revoke button. The
existing static-token section gains a deprecation notice.

"Connected" means **`revoked_at: nil`**, not Doorkeeper's `#accessible?`. Access tokens expire after
two hours; refresh tokens do not (see [Refresh-token rotation](#refresh-token-rotation)), so an
expired-but-unrevoked token is a working connection the client resumes whenever it likes. Filtering
on `#accessible?` hid every connection not in active use at that second, while
`ConnectedAppsController#destroy` scoped on `revoked_at` — which left revocation, the only such
control in the product, unreachable in the steady state. The list query and `#destroy` must stay the
same set. The granted-scope summary and the "connected since" date both derive from that set: the
union of scopes over unrevoked tokens (an expired one refreshes back into the same scopes, so the
client's reach is unchanged by the clock) and the earliest unrevoked token's date.

`#destroy` revokes the application's outstanding `Doorkeeper::AccessGrant`s alongside its tokens. An
unredeemed authorization code is a credential with a ten-minute life that exchanges into a fresh
access + refresh token pair, so leaving it would let a just-revoked connection walk back in.

The consent screen and this section are the only OAuth pages a human ever sees, and
`Oauth::AuthorizationsController` sets `layout -> { Layouts::ApplicationLayout }` so the first of
them renders as Cartodex. Doorkeeper's controllers descend from `ActionController::Base`, so Rails'
layout lookup otherwise climbs to `layouts/doorkeeper/application` — the gem's, which loads
`doorkeeper/application.css` and none of the app's design tokens. That is load-bearing rather than
cosmetic: the anti-phishing argument in [Consent screen](#consent-screen) rests on the user
recognising the page as Cartodex and reading the redirect host on it. It is set per-controller and
**not** through `Doorkeeper.configure { base_controller "ApplicationController" }`, because
`ApplicationController` carries `before_action :authenticate_user!`, which would collide with
`resource_owner_authenticator`'s own `store_location_for` redirect on the consent POST.

## Testing

Minitest with fixtures, as elsewhere in the repo.

The core is an integration test playing the whole flow — `test/integration/oauth_end_to_end_test.rb`.
It starts from nothing but the MCP URL and discovers every subsequent URL from the previous step's
response: the 401 challenge, the RFC 9728 protected-resource document, the RFC 8414
authorization-server document, dynamic registration, the consent screen **posted as the rendered form**
(the harvest helper is shared through `test/support/oauth_consent_form.rb` so it cannot diverge from
the screen a user really submits), code exchange with PKCE, `tools/list`, and a write call — plus
`state` surviving the round trip and the connection appearing in `/settings`. Around it, the negative
cases that matter:

- PKCE absent, and a wrong `code_verifier`
- an authorization code replayed
- `resource` pointing at something other than the canonical URI
- a redirect URI whose host is outside the allowlist
- the shape of both metadata documents, including that the `resource` field matches the MCP URL exactly
- the `WWW-Authenticate` header on the 401
- a read-only token whose `tools/list` excludes the six write tools, and which is refused on a direct write call
- consent with `mcp:write` unchecked producing a token without it
- the static bearer token still authenticating
- a refresh token replayed after the access token it minted has been used
- a `resource` that is an opaque URI (`urn:`, `mailto:`, `javascript:`), which has no path to
  normalise and used to 500 on an unauthenticated endpoint
- the consent screen rendering in the app's own layout, with the app's stylesheet

**Every one of these is verified by sabotage** — breaking the implementation in the specific way the
test is meant to catch, confirming the test goes red for the right reason, then restoring. A test
that cannot go red is not coverage.

## Out of scope

- OpenID Connect and `id_token`
- A token introspection endpoint
- Migrating to Doorkeeper 6.0
- A second protected resource
- Removing the static bearer token (a separate later change)

## Future direction

The draft MCP specification deprecates Dynamic Client Registration in favour of **OAuth Client ID
Metadata Documents**, where the client uses an HTTPS URL as its `client_id` and the authorization
server fetches the metadata from it. That removes the open registration endpoint and the phishing
surface the host allowlist exists to contain.

Claude works through DCR today, so DCR is what ships. When Claude supports Client ID Metadata
Documents, `/oauth/register`, its throttle, its purge job and possibly the host allowlist can all be
retired.

## Rollout

1. Ship OAuth alongside the static token.
2. Verify against a real Claude web connector.
3. Mark the static token deprecated in `/settings`, `CLAUDE.md` and the docs.
4. Remove it in a separate change, once CLI usage has moved to OAuth.
