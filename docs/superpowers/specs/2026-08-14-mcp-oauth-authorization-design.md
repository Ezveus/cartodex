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
| `force_pkce` | `true` | Required by OAuth 2.1. |
| `use_refresh_token` | `true` | Lets Claude refresh silently instead of re-prompting. |
| `hash_token_secrets` | enabled | Matches the choice already made for `api_token_digest`. |
| `hash_application_secrets` | enabled | Same. |
| `default_scopes` | `["mcp:read"]` | What a client gets when it requests no scope at all. |
| `optional_scopes` | `["mcp:write"]` | Grantable, and refusable at consent. |
| `skip_authorization` | `false` | Every user consents explicitly, every time a new client asks. |
| `resource_owner_authenticator` | Devise `current_user`, else redirect to sign-in with return | |

Three tables land in the `primary` database and therefore in `db/schema.rb`:
`oauth_applications`, `oauth_access_grants`, `oauth_access_tokens`.

### Routes

All of these sit **outside** the `authenticate :user` block in `config/routes.rb`. Doorkeeper handles
its own sign-in redirect through `resource_owner_authenticator`, and the metadata documents must be
publicly readable.

```ruby
use_doorkeeper do
  skip_controllers :applications, :authorized_applications
end

post "oauth/register", to: "oauth/registrations#create"
get ".well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
get ".well-known/oauth-protected-resource",     to: "oauth/metadata#protected_resource"
get ".well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"
```

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
| `app/services/oauth/client_registrar.rb` | Validates registration metadata, creates the application |
| `app/views/components/oauth/consent_view.rb` | Phlex consent screen |
| `app/views/components/settings/connected_apps_section.rb` | Connected applications + revocation |

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
Oauth::REGISTRABLE_REDIRECT_HOSTS = %w[claude.ai claude.com localhost 127.0.0.1].freeze
```

`claude.ai` is Claude's current callback host and `claude.com` is the announced successor; Anthropic
explicitly asks server operators to allowlist both. `localhost` and `127.0.0.1` cover CLI clients,
which use an ephemeral loopback callback port, and are the only hosts allowed over plain HTTP.
Anything else is rejected with `invalid_redirect_uri`. Supporting a new MCP client is a one-line
change plus a deploy — an acceptable price for closing the phishing vector almost entirely.

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

`authenticate_token!` tries a `Doorkeeper::AccessToken` first, then falls back to the existing static
token, with the fallback branch marked deprecated. One entry point, two identity sources,
`@current_user` unchanged for the rest of the controller.

## Scopes

Each tool class declares a `required_scope`: `mcp:read` by default, `mcp:write` for the six write
tools (`add_card_to_collection`, `set_collection_quantity`, `add_card_to_deck`,
`set_deck_card_owned_copies`, `reallocate_owned_copies`, `set_deck_card_quantity`).

Enforcement is doubled. `MCP::Server.new` receives only the tools covered by the token's scopes, so
`tools/list` never advertises an inaccessible tool; and `McpTool` re-checks in the call path, so a
client that guesses a tool name is still refused.

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

`/mcp` ends up with a per-IP limiter before authentication and a per-user limiter after it. The
per-user limiter covers **both** authentication paths without modification, since it keys on
`@current_user.id`. This shape is introduced by the separate `fix/mcp-rate-limit-per-user` change and
is a prerequisite for this one.

The pre-authentication IP bucket is the one remaining place where Anthropic's shared, rotating egress
IPs can cause false positives: every request without a valid token counts there, including each new
connector's initial 401 probe and every expired token. **Raise it from 30/min to 60/min as part of
this feature**, and revisit it against real traffic rather than guessing further.

## Settings

Skipping Doorkeeper's `:authorized_applications` controller means building its counterpart in Phlex:
the user's connected applications, with granted scopes, connection date, and a revoke button. The
existing static-token section gains a deprecation notice.

## Testing

Minitest with fixtures, as elsewhere in the repo.

The core is an integration test playing the whole flow — registration, authorize, consent, code
exchange, `/mcp` call. Around it, the negative cases that matter:

- PKCE absent, and a wrong `code_verifier`
- an authorization code replayed
- `resource` pointing at something other than the canonical URI
- a redirect URI whose host is outside the allowlist
- the shape of both metadata documents, including that the `resource` field matches the MCP URL exactly
- the `WWW-Authenticate` header on the 401
- a read-only token whose `tools/list` excludes the six write tools, and which is refused on a direct write call
- consent with `mcp:write` unchecked producing a token without it
- the static bearer token still authenticating

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
