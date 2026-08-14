# MCP OAuth Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Cartodex usable as a Claude web custom connector by turning it into its own OAuth 2.1 authorization server and OAuth-protected MCP resource.

**Architecture:** Doorkeeper 5.9.6 provides the authorization code flow, PKCE, refresh tokens, scopes and revocation. On top of it we add the four things it does not have and MCP requires: RFC 7591 dynamic client registration, the RFC 9728 and RFC 8414 metadata documents, the `WWW-Authenticate` challenge on the MCP endpoint, and RFC 8707 `resource` parameter validation. The existing static bearer token keeps working throughout.

**Tech Stack:** Rails 8.1, Ruby 3.4.1, SQLite, Devise 5, Doorkeeper 5.9.6, Phlex 2.2, the `mcp` gem 1.1, Minitest.

**Spec:** `docs/superpowers/specs/2026-08-14-mcp-oauth-authorization-design.md`

## Global Constraints

- **Doorkeeper version:** `~> 5.9`, resolving to 5.9.6. Do **not** use 6.0.0.beta — the spec explains why.
- **Scope names:** exactly `mcp:read` and `mcp:write`.
- **Canonical resource URI:** `https://cartodex.ezveus.eu/mcp` — no trailing slash, no fragment.
- **Allowlisted redirect hosts:** `claude.ai`, `claude.com`, `localhost`, `127.0.0.1`. The last two are the only ones permitted over plain HTTP.
- **All views are Phlex.** The single documented exception is the one-line ERB delegate in Task 6; no other ERB view may be created.
- **Business logic lives in `app/services/`**, controllers stay thin (see `CLAUDE.md`).
- **Code and code comments in English.**
- **Every new test must be sabotage-verified** — break the implementation in the way the test is meant to catch, confirm it goes red for the right reason, restore. Record what you broke in the commit body. A test that cannot go red is not coverage.
- **Lint and security gates:** `bin/rubocop` clean and no new `bin/brakeman --no-pager` warnings before every commit.

## Prerequisite

Task 3 modifies `app/controllers/mcp/server_controller.rb`. The rate-limit rework it builds on is **already merged** (commit `ff05411` on `master`); read that file before starting rather than assuming the shape below from this document. It is:

```ruby
before_action :identify_token_user            # sets @current_user, never halts
rate_limit …, name: "mcp-ip",  unless: -> { @current_user }   # 30/min, unauthenticated only
before_action :reject_unauthenticated!
rate_limit …, name: "mcp-user", by: -> { @current_user.id }   # 300/min, the real quota
```

The `unless:` is load-bearing and easy to destroy by accident. Both limiters are ordinary
`before_action`s, so without it an authenticated request increments both and its effective budget
becomes the smaller of the two — which is the bug that branch exists to fix. Any refactor of this
controller must keep the two callbacks separate and the condition intact.

## File Structure

| Path | Responsibility |
| --- | --- |
| `config/initializers/doorkeeper.rb` | Authorization server configuration |
| `db/migrate/*_create_doorkeeper_tables.rb` | `oauth_applications`, `oauth_access_grants`, `oauth_access_tokens` |
| `app/controllers/oauth/metadata_controller.rb` | The two `.well-known` documents |
| `app/controllers/oauth/registrations_controller.rb` | RFC 7591 endpoint, thin |
| `app/services/oauth/client_registrar.rb` | Registration metadata validation and application creation |
| `app/controllers/oauth/authorizations_controller.rb` | Doorkeeper subclass: `resource` validation |
| `app/views/doorkeeper/authorizations/new.html.erb` | One-line delegate to the Phlex consent view |
| `app/views/components/oauth/consent_view.rb` | Consent screen |
| `app/views/components/settings/connected_apps_section.rb` | Connected applications and revocation |
| `app/controllers/connected_apps_controller.rb` | Revoking a connected application |
| `app/jobs/oauth/purge_stale_applications_job.rb` | Deletes unused dynamically registered clients |
| `app/mcp/mcp_tool.rb` | Gains `required_scope` and its enforcement |

---

### Task 1: Install and configure Doorkeeper

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/doorkeeper.rb`
- Create: `db/migrate/<timestamp>_create_doorkeeper_tables.rb`
- Modify: `config/routes.rb`
- Modify: `db/schema.rb` (generated)
- Test: `test/integration/oauth_authorization_flow_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: the `Doorkeeper::Application`, `Doorkeeper::AccessGrant` and `Doorkeeper::AccessToken` models; the routes `/oauth/authorize` and `/oauth/token`; the scopes `mcp:read` and `mcp:write`.

- [ ] **Step 1: Add the gem**

```ruby
# Gemfile, right after the `gem "mcp", "~> 1.1"` line
# OAuth 2.1 authorization server, so MCP clients that cannot send a static
# bearer header (Claude web connectors) can authenticate.
gem "doorkeeper", "~> 5.9"
```

Run: `bundle install`

- [ ] **Step 2: Generate the installation and the migration**

```bash
bin/rails generate doorkeeper:install
bin/rails generate doorkeeper:migration
```

Open the generated migration. It **must** create `oauth_access_grants` with `code_challenge` and `code_challenge_method` columns. If those columns are absent, also run `bin/rails generate doorkeeper:pkce` and keep both migrations. PKCE is mandatory here, and the flow cannot work without those columns.

Remove `oauth_applications.owner_id`/`owner_type` from the migration if the generator emitted them: clients are created by dynamic registration, not owned by a user.

Run: `bin/rails db:migrate`

- [ ] **Step 3: Write the configuration**

Replace the generated `config/initializers/doorkeeper.rb` body with this. Delete the generator's commented boilerplate — the repo does not keep dead configuration.

```ruby
Doorkeeper.configure do
  orm :active_record

  # Doorkeeper runs its authorization endpoint inside the app's session, so the
  # resource owner is simply the signed-in Devise user. store_location_for makes
  # Devise return here after sign-in, which matters because the authorization
  # URL carries the PKCE challenge and state — losing it would break the flow.
  resource_owner_authenticator do
    current_user || begin
      store_location_for(:user, request.fullpath)
      redirect_to(new_user_session_path)
    end
  end

  # OAuth 2.1: authorization code only, PKCE mandatory. No implicit, no
  # password, no client credentials — an MCP client always acts for a user.
  grant_flows %w[authorization_code]
  force_pkce
  use_refresh_token

  # Same reasoning as users.api_token_digest: a database read must never yield a
  # usable credential.
  hash_token_secrets
  hash_application_secrets

  # mcp:read is what a client gets if it asks for nothing. mcp:write is optional
  # so the consent screen can withhold it and still produce a working connector.
  default_scopes  :"mcp:read"
  optional_scopes :"mcp:write"

  access_token_expires_in 2.hours

  # Every client must be consented to explicitly. Dynamic registration means any
  # party can create a client, so silent authorization would be a hole.
  skip_authorization { false }
end
```

- [ ] **Step 4: Mount the routes**

In `config/routes.rb`, immediately after the `match "mcp", …` line and **outside** the `authenticate :user` block, add:

```ruby
  # OAuth 2.1 authorization server. Outside the Devise `authenticate` block:
  # Doorkeeper redirects to sign-in itself through resource_owner_authenticator,
  # and wrapping it would break the return path.
  #
  # The applications and authorized_applications controllers are skipped: clients
  # are created by dynamic registration (Oauth::RegistrationsController), and the
  # user-facing list of connected apps is a Phlex section of /settings.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications
  end
```

- [ ] **Step 5: Write the failing test**

Create `test/integration/oauth_authorization_flow_test.rb`:

```ruby
require "test_helper"

class OauthAuthorizationFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @application = Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    @verifier = SecureRandom.urlsafe_base64(64)
    @challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(@verifier), padding: false
    )
  end

  def authorize_params(overrides = {})
    {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "mcp:read mcp:write",
      code_challenge: @challenge,
      code_challenge_method: "S256"
    }.merge(overrides)
  end

  # Pulls the authorization code out of the redirect Doorkeeper issues.
  def code_from_redirect
    Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
  end

  test "issues an access token through the authorization code flow with PKCE" do
    sign_in @user

    post "/oauth/authorize", params: authorize_params
    assert_response :redirect

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code_from_redirect,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid,
      client_secret: @application.plaintext_secret,
      code_verifier: @verifier
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].present?
    assert body["refresh_token"].present?
    assert_equal "mcp:read mcp:write", body["scope"]

    token = Doorkeeper::AccessToken.by_token(body["access_token"])
    assert_equal @user.id, token.resource_owner_id
  end

  test "rejects an authorization request that omits the PKCE challenge" do
    sign_in @user

    post "/oauth/authorize", params: authorize_params.except(:code_challenge, :code_challenge_method)

    # force_pkce turns a missing challenge into an invalid_request error rather
    # than silently issuing a code that any interceptor could redeem.
    assert_no_difference -> { Doorkeeper::AccessGrant.count } do
      assert_not_equal 302, response.status
    end
  end

  test "rejects a token exchange with the wrong code verifier" do
    sign_in @user
    post "/oauth/authorize", params: authorize_params
    code = code_from_redirect

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid,
      client_secret: @application.plaintext_secret,
      code_verifier: SecureRandom.urlsafe_base64(64)
    }

    assert_response :bad_request
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]
  end

  test "refuses to redeem the same authorization code twice" do
    sign_in @user
    post "/oauth/authorize", params: authorize_params
    code = code_from_redirect

    exchange = lambda do
      post "/oauth/token", params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: @application.redirect_uri,
        client_id: @application.uid,
        client_secret: @application.plaintext_secret,
        code_verifier: @verifier
      }
    end

    exchange.call
    assert_response :success

    exchange.call
    assert_response :bad_request
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]
  end
end
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `bin/rails test test/integration/oauth_authorization_flow_test.rb`
Expected: failures naming `uninitialized constant Doorkeeper` or a routing error for `/oauth/authorize`, before the configuration and migration are in place.

- [ ] **Step 7: Run the test to verify it passes**

Run: `bin/rails db:test:prepare && bin/rails test test/integration/oauth_authorization_flow_test.rb`
Expected: 4 runs, 0 failures.

If the PKCE test does not fail as expected, the `force_pkce` line is not taking effect — check the generated initializer's own comment for the exact form the installed version expects, and fix it. Do not delete the test.

- [ ] **Step 8: Sabotage-verify**

One at a time, then restore each:
- Comment out `force_pkce` → the missing-challenge test must go red.
- Change `grant_flows` to include `"implicit"` → the flow test must still pass (this one is a control; it proves the test is not accidentally asserting the grant list).
- Replace `hash_token_secrets` with nothing → the flow test still passes, but confirm by hand in the console that `Doorkeeper::AccessToken.last.token` is now the plaintext value, then restore. This documents why the setting matters even though no test pins it.

- [ ] **Step 9: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add Gemfile Gemfile.lock config/initializers/doorkeeper.rb config/routes.rb db/migrate db/schema.rb test/integration/oauth_authorization_flow_test.rb
git commit -m "feat: add Doorkeeper as the OAuth 2.1 authorization server"
```

---

### Task 2: The two metadata documents

**Files:**
- Create: `app/controllers/oauth/metadata_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/oauth/metadata_controller_test.rb`

**Interfaces:**
- Consumes: the Doorkeeper routes from Task 1.
- Produces: a private `#canonical_resource_uri`, the string `"#{root_url.chomp('/')}/mcp"`. It is an instance method, **not** a constant — the value is derived per request and a frozen constant could not hold it. Task 7 needs the same value and consolidates both into one definition; do not try to reuse this method from outside the controller.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/oauth/metadata_controller_test.rb`:

```ruby
require "test_helper"

module Oauth
  class MetadataControllerTest < ActionDispatch::IntegrationTest
    test "protected resource metadata points at this server and its scopes" do
      get "/.well-known/oauth-protected-resource"

      assert_response :success
      assert_equal "application/json", response.media_type
      body = JSON.parse(response.body)

      # The resource value must match the MCP URL exactly — a client that finds a
      # mismatch here is expected to abandon the flow.
      assert_equal "#{root_url.chomp('/')}/mcp", body["resource"]
      assert_equal [ root_url.chomp("/") ], body["authorization_servers"]
      assert_equal %w[mcp:read mcp:write], body["scopes_supported"]
      assert_equal [ "header" ], body["bearer_methods_supported"]
    end

    test "serves the protected resource metadata at the path-suffixed location too" do
      # RFC 9728 has the client insert the well-known segment before the
      # resource's path, so /mcp resolves to this URL. Clients disagree in
      # practice, so both must answer, identically.
      get "/.well-known/oauth-protected-resource/mcp"
      assert_response :success
      suffixed = response.body

      get "/.well-known/oauth-protected-resource"
      assert_equal suffixed, response.body
    end

    test "authorization server metadata advertises the endpoints and PKCE" do
      get "/.well-known/oauth-authorization-server"

      assert_response :success
      body = JSON.parse(response.body)

      assert_equal root_url.chomp("/"), body["issuer"]
      assert_equal "#{root_url.chomp('/')}/oauth/authorize", body["authorization_endpoint"]
      assert_equal "#{root_url.chomp('/')}/oauth/token", body["token_endpoint"]
      assert_equal "#{root_url.chomp('/')}/oauth/register", body["registration_endpoint"]
      assert_equal [ "code" ], body["response_types_supported"]
      assert_equal %w[authorization_code refresh_token], body["grant_types_supported"]
      assert_equal [ "S256" ], body["code_challenge_methods_supported"]
      assert_equal %w[mcp:read mcp:write], body["scopes_supported"]
    end

    test "metadata is reachable without authentication" do
      get "/.well-known/oauth-protected-resource"
      assert_response :success
      get "/.well-known/oauth-authorization-server"
      assert_response :success
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/oauth/metadata_controller_test.rb`
Expected: FAIL — `ActionController::RoutingError: No route matches [GET] "/.well-known/oauth-protected-resource"`.

- [ ] **Step 3: Write the controller**

Create `app/controllers/oauth/metadata_controller.rb`:

```ruby
module Oauth
  # The two discovery documents an MCP client fetches before it can authenticate:
  # RFC 9728 protected resource metadata (which authorization server guards this
  # resource) and RFC 8414 authorization server metadata (where its endpoints
  # are). Doorkeeper 5.9 ships neither; 6.0 ships the second one, at which point
  # #authorization_server can be dropped in favour of the gem's.
  #
  # Both are public and identical for every caller, so they are cacheable and
  # deliberately free of any request-derived state beyond the host.
  class MetadataController < ActionController::API
    SCOPES = %w[mcp:read mcp:write].freeze

    def protected_resource
      render json: {
        resource: canonical_resource_uri,
        authorization_servers: [ issuer ],
        scopes_supported: SCOPES,
        bearer_methods_supported: [ "header" ]
      }
    end

    def authorization_server
      render json: {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        registration_endpoint: "#{issuer}/oauth/register",
        revocation_endpoint: "#{issuer}/oauth/revoke",
        response_types_supported: [ "code" ],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post none],
        scopes_supported: SCOPES
      }
    end

    private

    # Derived from the request rather than hardcoded so development, test and
    # production each advertise themselves. The canonical form carries no
    # trailing slash — RFC 8707 asks for the most specific URI, consistently
    # written, and a client comparing strings will not normalise for us.
    def issuer
      root_url.chomp("/")
    end

    def canonical_resource_uri
      "#{issuer}/mcp"
    end
  end
end
```

- [ ] **Step 4: Add the routes**

In `config/routes.rb`, immediately after the `use_doorkeeper` block:

```ruby
  # Discovery documents. Public by necessity: a client reads them before it has
  # any credential. The protected-resource document answers at two paths — see
  # the controller for why.
  get ".well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get ".well-known/oauth-protected-resource",     to: "oauth/metadata#protected_resource"
  get ".well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/controllers/oauth/metadata_controller_test.rb`
Expected: 4 runs, 0 failures.

- [ ] **Step 6: Sabotage-verify**

- Change `canonical_resource_uri` to return `issuer` (dropping `/mcp`) → the first test must go red on the `resource` assertion.
- Delete the `.well-known/oauth-protected-resource/mcp` route → the second test must go red with a routing error.
- Change `code_challenge_methods_supported` to `%w[S256 plain]` → the third test must go red. This one matters: advertising `plain` would invite a client to downgrade PKCE.

- [ ] **Step 7: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/controllers/oauth/metadata_controller.rb config/routes.rb test/controllers/oauth/metadata_controller_test.rb
git commit -m "feat: serve OAuth protected resource and authorization server metadata"
```

---

### Task 3: Accept OAuth tokens on /mcp and challenge correctly

**Files:**
- Modify: `app/controllers/mcp/server_controller.rb`
- Test: `test/integration/mcp_server_test.rb`

**Interfaces:**
- Consumes: `Doorkeeper::AccessToken` (Task 1), the protected-resource URL (Task 2).
- Produces: `@current_user` resolved from either credential, and `@current_scopes` (an array of scope strings, `nil` for the legacy token) which Task 8 reads to filter tools.

**Depends on `fix/mcp-rate-limit-per-user` being merged.**

- [ ] **Step 1: Write the failing test**

Append to `test/integration/mcp_server_test.rb`:

```ruby
  test "authenticates a Doorkeeper access token" do
    application = Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    token = Doorkeeper::AccessToken.create!(
      application: application, resource_owner_id: @user.id, scopes: "mcp:read mcp:write"
    )

    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers(token: token.plaintext_token)

    assert_response :success
  end

  test "still authenticates the legacy static token" do
    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers

    assert_response :success
  end

  test "rejects a revoked Doorkeeper token" do
    application = Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read"
    )
    token = Doorkeeper::AccessToken.create!(
      application: application, resource_owner_id: @user.id, scopes: "mcp:read"
    )
    raw = token.plaintext_token
    token.revoke

    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers(token: raw)

    assert_response :unauthorized
  end

  test "challenges with the protected resource metadata URL on 401" do
    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers(token: "not-a-real-token")

    assert_response :unauthorized
    challenge = response.headers["WWW-Authenticate"]
    assert_includes challenge, "Bearer"
    assert_includes challenge, "resource_metadata=\"#{root_url.chomp('/')}/.well-known/oauth-protected-resource/mcp\""
    # No scope parameter: the client is meant to request everything the
    # protected-resource document advertises, and the consent screen arbitrates.
    assert_not_includes challenge, "scope="
  end

  test "challenges identically whether the token is absent, unknown or expired" do
    post "/mcp", params: rpc("list_decks", {}), headers: { "Content-Type" => "application/json" }
    absent = response.headers["WWW-Authenticate"]

    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers(token: "not-a-real-token")
    unknown = response.headers["WWW-Authenticate"]

    @user.update_column(:api_token_expires_at, 1.day.ago)
    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers
    expired = response.headers["WWW-Authenticate"]

    assert_equal absent, unknown
    assert_equal absent, expired
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/integration/mcp_server_test.rb`
Expected: the Doorkeeper-token test fails with `:unauthorized`, and both challenge tests fail with `nil` for the `WWW-Authenticate` header.

- [ ] **Step 3: Rewrite the authentication path**

In `app/controllers/mcp/server_controller.rb`, replace the bodies of `identify_token_user` and
`reject_unauthenticated!` (both introduced by the prerequisite branch) and add the helpers. Do **not**
merge them back into a single callback — the per-IP limiter's `unless:` condition sits between them
and depends on `@current_user` already being set:

```ruby
    def identify_token_user
      token = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
      authenticate_oauth_token(token) || authenticate_legacy_token(token)
    end

    def reject_unauthenticated!
      challenge! if @current_user.nil?
    end

    # An OAuth 2.1 access token issued by this app's own authorization server.
    # `accessible?` covers both expiry and revocation, so a revoked client's
    # tokens stop working the moment the user revokes it in /settings.
    def authenticate_oauth_token(token)
      access_token = Doorkeeper::AccessToken.by_token(token)
      return false unless access_token&.accessible?

      @current_user = User.find_by(id: access_token.resource_owner_id)
      return false if @current_user.nil?

      @current_scopes = access_token.scopes.to_a
      true
    end

    # Deprecated. The static per-user bearer token predates OAuth and stays only
    # so existing CLI configurations keep working; it is scheduled for removal
    # once OAuth has been verified against a real connector. It carries no
    # scopes, so it keeps full access — narrowing it now would break the very
    # setups this branch exists to preserve.
    def authenticate_legacy_token(token)
      @current_user = User.authenticate_api_token(token)
      @current_scopes = nil
      @current_user.present?
    end

    # RFC 9728: the 401 tells the client where to find the metadata that starts
    # the authorization flow. The challenge is byte-identical whether the token
    # was absent, unknown, expired or revoked — distinguishing them would let a
    # caller probe which tokens exist.
    def challenge!
      response.headers["WWW-Authenticate"] =
        %(Bearer resource_metadata="#{root_url.chomp('/')}/.well-known/oauth-protected-resource/mcp")
      head :unauthorized
    end
```

- [ ] **Step 4: Confirm the limiter split still holds**

No change to the limits. The prerequisite branch already scopes the per-IP limiter to unauthenticated
traffic via `unless: -> { @current_user }`, which is exactly what keeps Anthropic's shared egress IPs
from throttling unrelated users, so 30/min stays correct.

What this task *does* change is the shape of the two callbacks that limiter sits between. The
prerequisite branch splits authentication into `identify_token_user` (sets `@current_user`, never
halts) and `reject_unauthenticated!` (halts). Step 3 above replaces the body of both: `identify_token_user`
now tries the OAuth token first and the legacy token second, and `reject_unauthenticated!` becomes
`challenge!`. **Preserve the split and the `unless:` condition** — collapsing them back into one
`authenticate_token!` silently restores the bug the prerequisite branch exists to fix.

Verify with `bin/rails test test/integration/mcp_server_test.rb` that the prerequisite branch's
single-IP two-user test still passes after your rewrite. If it goes red, you have collapsed the split.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/integration/mcp_server_test.rb`
Expected: 0 failures.

- [ ] **Step 6: Sabotage-verify**

- Make `challenge!` emit the header only when the Authorization header was present → the identical-challenge test must go red on the absent-vs-unknown comparison.
- Replace `access_token&.accessible?` with `access_token.present?` → the revoked-token test must go red.
- Swap the order so the legacy token is tried first → all tests still pass; note in the commit body that order is not load-bearing for correctness, only for cost.

- [ ] **Step 7: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/controllers/mcp/server_controller.rb test/integration/mcp_server_test.rb
git commit -m "feat: authenticate MCP requests with OAuth tokens and challenge per RFC 9728"
```

---

### Task 4: Dynamic client registration

**Files:**
- Create: `app/services/oauth/client_registrar.rb`
- Create: `app/controllers/oauth/registrations_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/oauth/registrations_controller_test.rb`, `test/services/oauth/client_registrar_test.rb`

**Interfaces:**
- Consumes: `Doorkeeper::Application` (Task 1).
- Produces: `Oauth::ClientRegistrar.call(metadata) -> Doorkeeper::Application`, raising `Oauth::ClientRegistrar::InvalidMetadata` with a `#code` of `"invalid_redirect_uri"` or `"invalid_client_metadata"`; and the constant `Oauth::ClientRegistrar::ALLOWED_REDIRECT_HOSTS`.

- [ ] **Step 1: Write the failing service test**

Create `test/services/oauth/client_registrar_test.rb`:

```ruby
require "test_helper"

module Oauth
  class ClientRegistrarTest < ActiveSupport::TestCase
    def metadata(overrides = {})
      {
        "client_name" => "Claude",
        "redirect_uris" => [ "https://claude.ai/api/mcp/auth_callback" ],
        "grant_types" => %w[authorization_code refresh_token],
        "response_types" => [ "code" ],
        "token_endpoint_auth_method" => "client_secret_post",
        "scope" => "mcp:read mcp:write"
      }.merge(overrides)
    end

    test "creates a confidential application for an allowlisted redirect host" do
      application = ClientRegistrar.call(metadata)

      assert_equal "Claude", application.name
      assert_equal "https://claude.ai/api/mcp/auth_callback", application.redirect_uri
      assert_equal "mcp:read mcp:write", application.scopes.to_s
      assert application.confidential?
    end

    test "accepts claude.com as well as claude.ai" do
      application = ClientRegistrar.call(
        metadata("redirect_uris" => [ "https://claude.com/api/mcp/auth_callback" ])
      )

      assert_equal "https://claude.com/api/mcp/auth_callback", application.redirect_uri
    end

    test "accepts a loopback callback over plain HTTP for CLI clients" do
      application = ClientRegistrar.call(
        metadata("redirect_uris" => [ "http://127.0.0.1:49152/callback" ])
      )

      assert_equal "http://127.0.0.1:49152/callback", application.redirect_uri
    end

    test "creates a public application when the client authenticates with none" do
      application = ClientRegistrar.call(metadata("token_endpoint_auth_method" => "none"))

      assert_not application.confidential?
    end

    test "rejects a redirect host outside the allowlist" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata("redirect_uris" => [ "https://evil.example.com/callback" ]))
      end

      assert_equal "invalid_redirect_uri", error.code
      assert_equal 0, Doorkeeper::Application.count
    end

    test "rejects plain HTTP on a non-loopback host" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata("redirect_uris" => [ "http://claude.ai/api/mcp/auth_callback" ]))
      end

      assert_equal "invalid_redirect_uri", error.code
    end

    test "rejects a redirect URI carrying a fragment" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(
          metadata("redirect_uris" => [ "https://claude.ai/api/mcp/auth_callback#x" ])
        )
      end

      assert_equal "invalid_redirect_uri", error.code
    end

    test "rejects metadata with no redirect_uris at all" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata.except("redirect_uris"))
      end

      assert_equal "invalid_redirect_uri", error.code
    end

    test "rejects a scope outside the server's own" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata("scope" => "mcp:read admin"))
      end

      assert_equal "invalid_client_metadata", error.code
    end

    test "falls back to both scopes when the client requests none" do
      application = ClientRegistrar.call(metadata.except("scope"))

      assert_equal "mcp:read mcp:write", application.scopes.to_s
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/services/oauth/client_registrar_test.rb`
Expected: FAIL — `NameError: uninitialized constant Oauth::ClientRegistrar`.

- [ ] **Step 3: Write the service**

Create `app/services/oauth/client_registrar.rb`:

```ruby
module Oauth
  # RFC 7591 dynamic client registration.
  #
  # The endpoint that calls this is necessarily unauthenticated — a client has no
  # credential before it registers. That makes the redirect-URI allowlist the
  # load-bearing control: without it, anyone can register a client pointing at
  # their own server, name it "Claude", and phish a Cartodex user into
  # authorizing it. client_name comes straight from the request and is entirely
  # attacker-controlled, so it can never be part of a security decision.
  class ClientRegistrar < ApplicationService
    class InvalidMetadata < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    # Anthropic asks operators to allowlist both of its callback hosts:
    # claude.ai is current, claude.com is the announced successor. The loopback
    # hosts cover CLI clients, which bind an ephemeral local port.
    ALLOWED_REDIRECT_HOSTS = %w[claude.ai claude.com localhost 127.0.0.1].freeze

    # Only the loopback hosts may drop TLS: there is no network to intercept.
    PLAIN_HTTP_HOSTS = %w[localhost 127.0.0.1].freeze

    SERVER_SCOPES = %w[mcp:read mcp:write].freeze

    def initialize(metadata)
      @metadata = metadata
    end

    def call
      Doorkeeper::Application.create!(
        name: client_name,
        redirect_uri: redirect_uris.join("\n"),
        scopes: scopes,
        confidential: confidential?
      )
    end

    private

    attr_reader :metadata

    def client_name
      name = metadata["client_name"].to_s.strip
      name.presence || "Unnamed MCP client"
    end

    def redirect_uris
      uris = Array(metadata["redirect_uris"]).map(&:to_s).reject(&:blank?)
      raise InvalidMetadata.new("invalid_redirect_uri", "redirect_uris is required") if uris.empty?

      uris.each { |uri| validate_redirect_uri!(uri) }
    end

    def validate_redirect_uri!(raw)
      uri = URI.parse(raw)
      reject_uri!(raw) unless uri.absolute? && uri.fragment.nil?
      reject_uri!(raw) unless ALLOWED_REDIRECT_HOSTS.include?(uri.host)
      reject_uri!(raw) unless uri.scheme == "https" ||
                              (uri.scheme == "http" && PLAIN_HTTP_HOSTS.include?(uri.host))
    rescue URI::InvalidURIError
      reject_uri!(raw)
    end

    def reject_uri!(raw)
      raise InvalidMetadata.new("invalid_redirect_uri", "#{raw} is not an acceptable redirect URI")
    end

    # A client that names no scope gets both, which is what Claude does when it
    # follows scopes_supported from the protected-resource document. The consent
    # screen, not registration, is where a user narrows this down.
    def scopes
      requested = metadata["scope"].to_s.split
      return SERVER_SCOPES.join(" ") if requested.empty?

      unknown = requested - SERVER_SCOPES
      if unknown.any?
        raise InvalidMetadata.new("invalid_client_metadata", "unknown scope: #{unknown.join(' ')}")
      end

      requested.join(" ")
    end

    def confidential?
      metadata["token_endpoint_auth_method"].to_s != "none"
    end
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bin/rails test test/services/oauth/client_registrar_test.rb`
Expected: 10 runs, 0 failures.

- [ ] **Step 5: Write the failing controller test**

Create `test/controllers/oauth/registrations_controller_test.rb`:

```ruby
require "test_helper"

module Oauth
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    def register(metadata)
      post "/oauth/register",
        params: metadata.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    def valid_metadata
      {
        client_name: "Claude",
        redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ],
        token_endpoint_auth_method: "client_secret_post"
      }
    end

    test "registers a client and returns RFC 7591 credentials" do
      register(valid_metadata)

      assert_response :created
      body = JSON.parse(response.body)
      assert body["client_id"].present?
      assert body["client_secret"].present?
      assert body["client_id_issued_at"].present?
      # 0 means the secret does not expire, per RFC 7591.
      assert_equal 0, body["client_secret_expires_at"]
      assert_equal [ "https://claude.ai/api/mcp/auth_callback" ], body["redirect_uris"]
    end

    test "the returned credentials actually work at the token endpoint" do
      register(valid_metadata)
      credentials = JSON.parse(response.body)

      application = Doorkeeper::Application.find_by(uid: credentials["client_id"])
      assert_not_nil application
      assert application.secret_matches?(credentials["client_secret"])
    end

    test "omits client_secret for a public client" do
      register(valid_metadata.merge(token_endpoint_auth_method: "none"))

      assert_response :created
      assert_nil JSON.parse(response.body)["client_secret"]
    end

    test "rejects a redirect host outside the allowlist" do
      register(valid_metadata.merge(redirect_uris: [ "https://evil.example.com/cb" ]))

      assert_response :bad_request
      assert_equal "invalid_redirect_uri", JSON.parse(response.body)["error"]
      assert_equal 0, Doorkeeper::Application.count
    end

    test "requires no authentication" do
      register(valid_metadata)

      assert_response :created
    end
  end
end
```

- [ ] **Step 6: Run it to verify it fails**

Run: `bin/rails test test/controllers/oauth/registrations_controller_test.rb`
Expected: FAIL — routing error for `POST /oauth/register`.

- [ ] **Step 7: Write the controller**

Create `app/controllers/oauth/registrations_controller.rb`:

```ruby
module Oauth
  # RFC 7591 registration endpoint. ActionController::API rather than ::Base:
  # this is a machine endpoint with no session and no CSRF token to present.
  #
  # Unauthenticated by necessity, so it is throttled per IP — the one place in
  # this feature where an IP key is the right choice, because no user exists yet.
  class RegistrationsController < ActionController::API
    RATE_LIMIT_TO = 20
    RATE_LIMIT_WITHIN = 1.minute

    # Same call-time Rails.cache proxy as Mcp::ServerController, so tests can
    # swap in a real store where the test environment's :null_store would make
    # the limiter a no-op.
    RATE_LIMIT_STORE = Module.new do
      def self.increment(...)
        Rails.cache.increment(...)
      end
    end

    rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
      name: "oauth-register", store: RATE_LIMIT_STORE, only: :create

    def create
      application = ClientRegistrar.call(registration_metadata)

      render json: registration_response(application), status: :created
    rescue ClientRegistrar::InvalidMetadata => e
      render json: { error: e.code, error_description: e.message }, status: :bad_request
    end

    private

    # params.to_unsafe_h is deliberate: RFC 7591 metadata is an open map whose
    # keys are defined by the RFC and its extensions, not by us. The service
    # reads only the keys it knows and validates each one, so permitting a fixed
    # list here would add no safety and would silently drop future metadata.
    def registration_metadata
      params.to_unsafe_h.except("controller", "action", "registration").stringify_keys
    end

    def registration_response(application)
      {
        client_id: application.uid,
        client_secret: application.confidential? ? application.plaintext_secret : nil,
        client_id_issued_at: application.created_at.to_i,
        client_secret_expires_at: 0,
        client_name: application.name,
        redirect_uris: application.redirect_uri.split("\n"),
        grant_types: %w[authorization_code refresh_token],
        response_types: [ "code" ],
        token_endpoint_auth_method: application.confidential? ? "client_secret_post" : "none",
        scope: application.scopes.to_s
      }.compact
    end
  end
end
```

- [ ] **Step 8: Add the route**

In `config/routes.rb`, next to the metadata routes:

```ruby
  post "oauth/register", to: "oauth/registrations#create"
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/oauth/registrations_controller_test.rb test/services/oauth/client_registrar_test.rb`
Expected: 15 runs, 0 failures.

- [ ] **Step 10: Sabotage-verify**

- Remove the `ALLOWED_REDIRECT_HOSTS.include?` check → both allowlist tests must go red.
- Allow `http` on any host → the plain-HTTP test must go red.
- Drop the `uri.fragment.nil?` condition → the fragment test must go red.
- Return `plaintext_secret` for public clients too → the public-client test must go red.

- [ ] **Step 11: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/services/oauth/client_registrar.rb app/controllers/oauth/registrations_controller.rb config/routes.rb test/services/oauth test/controllers/oauth/registrations_controller_test.rb
git commit -m "feat: implement RFC 7591 dynamic client registration with a redirect host allowlist"
```

Brakeman will likely flag the unauthenticated `create`. Confirm it is the expected warning and add it to the ignore file with a comment naming the allowlist as the compensating control — do not silence it blindly.

---

### Task 5: Purge stale registered clients

**Files:**
- Create: `app/jobs/oauth/purge_stale_applications_job.rb`
- Modify: `config/recurring.yml`
- Test: `test/jobs/oauth/purge_stale_applications_job_test.rb`

**Interfaces:**
- Consumes: `Doorkeeper::Application` (Task 1).
- Produces: nothing other code reads.

- [ ] **Step 1: Write the failing test**

Create `test/jobs/oauth/purge_stale_applications_job_test.rb`:

```ruby
require "test_helper"

module Oauth
  class PurgeStaleApplicationsJobTest < ActiveJob::TestCase
    def application(created_at:)
      Doorkeeper::Application.create!(
        name: "Client",
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        scopes: "mcp:read"
      ).tap { |a| a.update_column(:created_at, created_at) }
    end

    test "deletes an old application that was never used" do
      stale = application(created_at: 8.days.ago)

      PurgeStaleApplicationsJob.perform_now

      assert_not Doorkeeper::Application.exists?(stale.id)
    end

    test "keeps a recent application that has not been used yet" do
      # Registration and authorization are separate round-trips; a client that
      # registered a minute ago has not had the chance to be authorized.
      fresh = application(created_at: 1.hour.ago)

      PurgeStaleApplicationsJob.perform_now

      assert Doorkeeper::Application.exists?(fresh.id)
    end

    test "keeps an old application that holds an access token" do
      used = application(created_at: 30.days.ago)
      Doorkeeper::AccessToken.create!(
        application: used, resource_owner_id: users(:one).id, scopes: "mcp:read"
      )

      PurgeStaleApplicationsJob.perform_now

      assert Doorkeeper::Application.exists?(used.id)
    end

    test "keeps an old application that holds an access grant" do
      used = application(created_at: 30.days.ago)
      Doorkeeper::AccessGrant.create!(
        application: used, resource_owner_id: users(:one).id, scopes: "mcp:read",
        redirect_uri: used.redirect_uri, expires_in: 600
      )

      PurgeStaleApplicationsJob.perform_now

      assert Doorkeeper::Application.exists?(used.id)
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/jobs/oauth/purge_stale_applications_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant Oauth::PurgeStaleApplicationsJob`.

- [ ] **Step 3: Write the job**

Create `app/jobs/oauth/purge_stale_applications_job.rb`:

```ruby
module Oauth
  # Registration is open to anyone, so scanners and abandoned setup attempts
  # would grow oauth_applications without bound. An application that has neither
  # an access grant nor an access token was never authorized by anyone: deleting
  # it can cost nobody a working connector.
  #
  # The grace period is generous on purpose. Registration and authorization are
  # separate round-trips, and a user who registers then goes to find their
  # password must still be able to finish.
  class PurgeStaleApplicationsJob < ApplicationJob
    queue_as :default

    GRACE_PERIOD = 7.days

    def perform
      Doorkeeper::Application
        .where(created_at: ..GRACE_PERIOD.ago)
        .where.missing(:access_tokens)
        .where.missing(:access_grants)
        .destroy_all
    end
  end
end
```

If `Doorkeeper::Application` does not declare `has_many :access_grants`, `where.missing(:access_grants)` raises. Confirm both associations exist on the installed version; if `access_grants` is absent, replace that clause with:

```ruby
        .where.not(id: Doorkeeper::AccessGrant.select(:application_id))
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bin/rails test test/jobs/oauth/purge_stale_applications_job_test.rb`
Expected: 4 runs, 0 failures.

- [ ] **Step 5: Schedule it**

In `config/recurring.yml`, under the production section:

```yaml
  purge_stale_oauth_applications:
    class: Oauth::PurgeStaleApplicationsJob
    schedule: every day at 4am
```

If `config/recurring.yml` has no production section yet, add one following the file's existing structure.

- [ ] **Step 6: Sabotage-verify**

- Drop the `where.missing(:access_tokens)` clause → the access-token test must go red.
- Change `GRACE_PERIOD` to `1.minute` → the fresh-application test must go red.

- [ ] **Step 7: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/jobs/oauth config/recurring.yml test/jobs/oauth
git commit -m "feat: purge dynamically registered OAuth clients that were never authorized"
```

---

### Task 6: Consent screen with refusable write scope

**Files:**
- Create: `app/views/components/oauth/consent_view.rb`
- Create: `app/views/doorkeeper/authorizations/new.html.erb`
- Modify: `config/routes.rb`
- Create: `app/controllers/oauth/authorizations_controller.rb`
- Test: `test/integration/oauth_consent_test.rb`

**Interfaces:**
- Consumes: Doorkeeper's `pre_auth` object (Task 1).
- Produces: `Oauth::AuthorizationsController`, which Task 7 extends with `resource` validation.

- [ ] **Step 1: Write the failing test**

Create `test/integration/oauth_consent_test.rb`:

```ruby
require "test_helper"

class OauthConsentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @application = Doorkeeper::Application.create!(
      name: "Claude",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    @verifier = SecureRandom.urlsafe_base64(64)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
  end

  def authorize_params(overrides = {})
    {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "mcp:read mcp:write",
      code_challenge: @challenge,
      code_challenge_method: "S256"
    }.merge(overrides)
  end

  def granted_scopes
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
    Doorkeeper::AccessGrant.find_by(token: code)&.scopes.to_s
  end

  test "redirects an anonymous visitor to sign in and back to the authorization" do
    get "/oauth/authorize", params: authorize_params

    assert_redirected_to new_user_session_path
  end

  test "shows the client name and the redirect host on the consent screen" do
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_select "[data-testid='consent-client-name']", text: /Claude/
    # The name is self-declared and worthless as identity; the host is what a
    # user can actually judge, so it must be on screen.
    assert_select "[data-testid='consent-redirect-host']", text: /claude\.ai/
  end

  test "grants both scopes when write is left checked" do
    sign_in @user

    post "/oauth/authorize", params: authorize_params

    assert_response :redirect
    assert_equal "mcp:read mcp:write", granted_scopes
  end

  test "grants read only when write is unchecked" do
    sign_in @user

    # Unchecking the box makes the browser post the narrower scope string.
    post "/oauth/authorize", params: authorize_params(scope: "mcp:read")

    assert_response :redirect
    assert_equal "mcp:read", granted_scopes
  end

  test "escapes a client name that tries to inject markup" do
    @application.update!(name: "<script>alert(1)</script>")
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/integration/oauth_consent_test.rb`
Expected: the `assert_select` tests fail — Doorkeeper's stock view has neither test id.

**If the "grants read only" test already passes at this point, good:** Doorkeeper accepts a narrowed `scope` on the POST without further work, and the form alone is enough. **If it fails** with an `invalid_scope` error, Doorkeeper is re-validating against the original request; in that case add this to the controller in Step 5 and re-run:

```ruby
    # Doorkeeper rebuilds pre_auth from params on POST. When it refuses a scope
    # narrower than the one first requested, the consent form's choice has to be
    # applied before that rebuild happens.
    before_action :narrow_scopes_to_consent, only: :create

    def narrow_scopes_to_consent
      granted = Array(params[:granted_scopes]).reject(&:blank?)
      params[:scope] = (granted & Oauth::MetadataController::SCOPES).join(" ") if granted.any?
    end
```

- [ ] **Step 3: Write the consent component**

Create `app/views/components/oauth/consent_view.rb`:

```ruby
module Oauth
  # The consent screen. Two things are on trial here, and the layout should make
  # the difference obvious: the client's name, which it chose for itself at
  # registration and which an attacker controls freely, and the host it will send
  # the authorization code to, which the redirect-URI allowlist has already
  # constrained and which the user can actually reason about.
  class ConsentView < ApplicationComponent
    SCOPE_DESCRIPTIONS = {
      "mcp:read" => "Read your collection, your decks and your results",
      "mcp:write" => "Add and modify cards in your collection and your decks"
    }.freeze

    def initialize(pre_auth:)
      @pre_auth = pre_auth
    end

    def view_template
      section(class: "settings-section") do
        h2 { "Authorize a connection" }
        client_identity
        scope_form
      end
    end

    private

    def client_identity
      p(class: "settings-section-lead") do
        strong(data: { testid: "consent-client-name" }) { @pre_auth.client.name }
        plain " wants access to your Cartodex account."
      end
      p(class: "settings-section-lead") do
        plain "It will be sent back to "
        code(data: { testid: "consent-redirect-host" }) { redirect_host }
        plain ". Only continue if you recognise that address."
      end
    end

    def redirect_host
      URI.parse(@pre_auth.redirect_uri).host
    rescue URI::InvalidURIError
      @pre_auth.redirect_uri
    end

    def scope_form
      form_with(url: oauth_authorization_path, method: :post) do
        hidden_fields
        fieldset do
          legend { "Permissions" }
          requested_scopes.each { |scope| scope_checkbox(scope) }
        end
        button(type: "submit", class: "button-primary") { "Authorize" }
      end
      form_with(url: oauth_authorization_path, method: :delete) do
        hidden_fields
        button(type: "submit", class: "button-secondary") { "Deny" }
      end
    end

    # Everything Doorkeeper needs to rebuild the request, PKCE challenge
    # included. Losing any of these silently downgrades or breaks the flow.
    def hidden_fields
      {
        client_id: @pre_auth.client.uid,
        redirect_uri: @pre_auth.redirect_uri,
        state: @pre_auth.state,
        response_type: @pre_auth.response_type,
        code_challenge: @pre_auth.code_challenge,
        code_challenge_method: @pre_auth.code_challenge_method
      }.each do |name, value|
        input(type: "hidden", name: name, value: value) if value.present?
      end
    end

    def requested_scopes
      @pre_auth.scopes.to_a
    end

    # mcp:read is shown but not refusable: a connector without it can do nothing
    # at all, so offering to remove it would only produce a dead client.
    def scope_checkbox(scope)
      required = scope == "mcp:read"

      label(class: "consent-scope") do
        input(
          type: "checkbox", name: "granted_scopes[]", value: scope,
          checked: true, disabled: required
        )
        plain SCOPE_DESCRIPTIONS.fetch(scope, scope)
      end
      input(type: "hidden", name: "granted_scopes[]", value: scope) if required
    end
  end
end
```

Note the hidden mirror of the disabled `mcp:read` checkbox: a disabled input is not submitted, so without it the required scope would silently vanish from the POST.

- [ ] **Step 4: Add the one-line ERB delegate**

Create `app/views/doorkeeper/authorizations/new.html.erb` containing exactly:

```erb
<%# Doorkeeper renders its authorization screen by view lookup, which is the
    stable seam for replacing it. This file exists only to hand off to the Phlex
    component — it holds no view logic, and it is the single ERB view in the app. %>
<%= render Oauth::ConsentView.new(pre_auth: @pre_auth) %>
```

- [ ] **Step 5: Point the route at our controller**

Create `app/controllers/oauth/authorizations_controller.rb`:

```ruby
module Oauth
  # Subclasses Doorkeeper's authorization endpoint. It exists so the consent
  # screen and the RFC 8707 resource check (added in the next task) have a home;
  # the authorization logic itself stays Doorkeeper's.
  class AuthorizationsController < Doorkeeper::AuthorizationsController
  end
end
```

In `config/routes.rb`, extend the `use_doorkeeper` block:

```ruby
  use_doorkeeper do
    controllers authorizations: "oauth/authorizations"
    skip_controllers :applications, :authorized_applications
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/integration/oauth_consent_test.rb`
Expected: 5 runs, 0 failures.

- [ ] **Step 7: Sabotage-verify**

- Delete the hidden mirror of the required scope → the "grants both scopes" test must go red, or the grant must come back without `mcp:read`.
- Drop `code_challenge` from `hidden_fields` → the consent POST must stop producing a redeemable grant; confirm `test/integration/oauth_authorization_flow_test.rb` still passes, since it posts directly and does not go through the form.
- Render the client name with `raw` → the markup-injection test must go red.

- [ ] **Step 8: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/views/components/oauth app/views/doorkeeper app/controllers/oauth/authorizations_controller.rb config/routes.rb test/integration/oauth_consent_test.rb
git commit -m "feat: add a Phlex consent screen with a refusable write scope"
```

---

### Task 7: Validate the RFC 8707 resource parameter

**Files:**
- Modify: `app/controllers/oauth/authorizations_controller.rb`
- Create: `app/controllers/oauth/tokens_controller.rb`
- Create: `app/services/oauth/resource_indicator.rb`
- Create: `app/controllers/concerns/oauth/resource_indicator_enforcement.rb`
- Modify: `app/controllers/oauth/metadata_controller.rb` — replace its private `canonical_resource_uri` body with `ResourceIndicator.canonical_uri(root_url)`, so the canonical value has one definition rather than two. Task 2's own tests must still pass unchanged; if they do not, the two definitions had already diverged and that is a finding to report.
- Modify: `config/routes.rb`
- Test: `test/integration/oauth_resource_indicator_test.rb`

**Interfaces:**
- Consumes: `Oauth::MetadataController` for the canonical URI shape (Task 2), `Oauth::AuthorizationsController` (Task 6).
- Produces: `Oauth::ResourceIndicator.valid?(value, canonical_uri)` — two Strings, not a request object — shared by both controllers through `Oauth::ResourceIndicatorEnforcement`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/oauth_resource_indicator_test.rb`:

```ruby
require "test_helper"

class OauthResourceIndicatorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @application = Doorkeeper::Application.create!(
      name: "Claude",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    @verifier = SecureRandom.urlsafe_base64(64)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
    sign_in @user
  end

  def authorize_params(overrides = {})
    {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "mcp:read",
      code_challenge: @challenge,
      code_challenge_method: "S256"
    }.merge(overrides)
  end

  test "accepts an authorization carrying the canonical resource URI" do
    post "/oauth/authorize", params: authorize_params(resource: "#{root_url.chomp('/')}/mcp")

    assert_response :redirect
  end

  test "accepts an authorization with no resource parameter at all" do
    # The specification obliges clients to send it; refusing those that do not
    # would cost interoperability and buy nothing while we host one resource.
    post "/oauth/authorize", params: authorize_params

    assert_response :redirect
  end

  test "accepts an uppercase scheme and host" do
    post "/oauth/authorize", params: authorize_params(
      resource: "HTTPS://#{URI.parse(root_url).host.upcase}/mcp"
    )

    assert_response :redirect
  end

  test "rejects an authorization aimed at another resource" do
    post "/oauth/authorize", params: authorize_params(resource: "https://evil.example.com/mcp")

    assert_response :bad_request
    assert_equal "invalid_target", JSON.parse(response.body)["error"]
  end

  test "rejects a resource carrying a fragment" do
    post "/oauth/authorize", params: authorize_params(resource: "#{root_url.chomp('/')}/mcp#x")

    assert_response :bad_request
    assert_equal "invalid_target", JSON.parse(response.body)["error"]
  end

  test "rejects a token request aimed at another resource" do
    post "/oauth/authorize", params: authorize_params
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid, client_secret: @application.plaintext_secret,
      code_verifier: @verifier, resource: "https://evil.example.com/mcp"
    }

    assert_response :bad_request
    assert_equal "invalid_target", JSON.parse(response.body)["error"]
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/integration/oauth_resource_indicator_test.rb`
Expected: the three rejection tests fail — the parameter is currently ignored, so every request redirects or succeeds.

- [ ] **Step 3: Write the shared validator**

Create `app/services/oauth/resource_indicator.rb`:

```ruby
module Oauth
  # RFC 8707 resource indicators. Doorkeeper 5.9 ignores the parameter entirely
  # (6.0 gains resource_indicator_validator), so both endpoints check it here.
  #
  # Cartodex hosts exactly one protected resource, so "was this token issued for
  # us" reduces to "does the requested resource name us". THAT EQUIVALENCE ENDS
  # THE DAY A SECOND PROTECTED RESOURCE EXISTS: at that point the resource has to
  # be stored on the token and re-checked when the token is presented.
  module ResourceIndicator
    module_function

    # The one definition of what "this resource" means. Both the metadata
    # document (which advertises it) and the two OAuth endpoints (which validate
    # against it) call this, so the advertised value and the accepted value
    # cannot drift apart.
    def canonical_uri(root_url)
      "#{root_url.chomp('/')}/mcp"
    end

    # Absent is acceptable; present and wrong is not.
    def valid?(value, canonical_uri)
      return true if value.blank?

      uri = URI.parse(value.to_s)
      return false unless uri.fragment.nil?

      # RFC 8707 canonical form is lowercase scheme and host, but the MCP
      # specification asks servers to accept uppercase for robustness. The path
      # is compared as-is: it is case-sensitive by RFC 3986.
      normalize(uri) == canonical_uri
    rescue URI::InvalidURIError
      false
    end

    def normalize(uri)
      "#{uri.scheme&.downcase}://#{uri.host&.downcase}#{":#{uri.port}" unless uri.default_port == uri.port}#{uri.path.chomp('/')}"
    end
  end
end
```

- [ ] **Step 4: Enforce it on both endpoints**

Replace `app/controllers/oauth/authorizations_controller.rb` with:

```ruby
module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    include ResourceIndicatorEnforcement
  end
end
```

Create `app/controllers/concerns/oauth/resource_indicator_enforcement.rb`:

```ruby
module Oauth
  # Shared by the authorization and token endpoints so a client cannot pass the
  # check at one and slip a different resource past the other.
  module ResourceIndicatorEnforcement
    extend ActiveSupport::Concern

    included do
      before_action :validate_resource_indicator!
    end

    private

    def validate_resource_indicator!
      return if ResourceIndicator.valid?(params[:resource], canonical_resource_uri)

      render json: {
        error: "invalid_target",
        error_description: "resource must be #{canonical_resource_uri}"
      }, status: :bad_request
    end

    # Delegates so the canonical URI has exactly one definition. Task 2 built the
    # same expression privately in Oauth::MetadataController; this task moves the
    # single copy into ResourceIndicator and points both callers at it. Two
    # independent definitions of this value would be a real hazard, not a style
    # nit: if they ever diverged, the metadata document would advertise one
    # resource while the token endpoint accepted another.
    def canonical_resource_uri
      ResourceIndicator.canonical_uri(root_url)
    end
  end
end
```

Create `app/controllers/oauth/tokens_controller.rb`:

```ruby
module Oauth
  class TokensController < Doorkeeper::TokensController
    include ResourceIndicatorEnforcement
  end
end
```

And extend the routes block:

```ruby
  use_doorkeeper do
    controllers authorizations: "oauth/authorizations", tokens: "oauth/tokens"
    skip_controllers :applications, :authorized_applications
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/integration/oauth_resource_indicator_test.rb test/integration/oauth_authorization_flow_test.rb`
Expected: 10 runs, 0 failures.

- [ ] **Step 6: Sabotage-verify**

- Make `valid?` return `false` for a blank value → the no-parameter test must go red.
- Drop the `downcase` calls in `normalize` → the uppercase test must go red.
- Include `ResourceIndicatorEnforcement` in the authorizations controller only → the token-endpoint test must go red.

- [ ] **Step 7: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/services/oauth/resource_indicator.rb app/controllers/concerns/oauth app/controllers/oauth config/routes.rb test/integration/oauth_resource_indicator_test.rb
git commit -m "feat: validate the RFC 8707 resource parameter on both OAuth endpoints"
```

---

### Task 8: Enforce scopes on MCP tools

**Files:**
- Modify: `app/mcp/mcp_tool.rb`
- Modify: the six write tools in `app/mcp/`
- Modify: `app/controllers/mcp/server_controller.rb`
- Test: `test/integration/mcp_scope_test.rb`

**Interfaces:**
- Consumes: `@current_scopes` from Task 3.
- Produces: `McpTool.required_scope` (a String) on every tool class, and `McpTool.permitted_for(scopes)`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/mcp_scope_test.rb`:

```ruby
require "test_helper"

class McpScopeTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @card = cards(:trainer_card)
    @application = Doorkeeper::Application.create!(
      name: "Claude",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
  end

  def token_with(scopes)
    Doorkeeper::AccessToken.create!(
      application: @application, resource_owner_id: @user.id, scopes: scopes
    ).plaintext_token
  end

  def headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream"
    }
  end

  def list_tools(token)
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
      headers: headers(token)
    JSON.parse(response.body).dig("result", "tools").map { |t| t["name"] }
  end

  WRITE_TOOLS = %w[
    add_card_to_collection set_collection_quantity add_card_to_deck
    set_deck_card_owned_copies reallocate_owned_copies set_deck_card_quantity
  ].freeze

  test "a read-only token sees no write tools" do
    names = list_tools(token_with("mcp:read"))

    assert_includes names, "list_decks"
    WRITE_TOOLS.each { |tool| assert_not_includes names, tool }
  end

  test "a read-write token sees every tool" do
    names = list_tools(token_with("mcp:read mcp:write"))

    WRITE_TOOLS.each { |tool| assert_includes names, tool }
  end

  test "a read-only token cannot call a write tool it was never shown" do
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                params: { name: "add_card_to_collection",
                          arguments: { card_id: @card.id, quantity: 1 } } }.to_json,
      headers: headers(token_with("mcp:read"))

    assert_nil @user.collections.find_by(card: @card)
  end

  test "the legacy static token keeps access to every tool" do
    # It carries no scopes; narrowing it would break the setups the deprecation
    # window exists to preserve.
    names = list_tools(@user.regenerate_api_token)

    WRITE_TOOLS.each { |tool| assert_includes names, tool }
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/integration/mcp_scope_test.rb`
Expected: the read-only tests fail — every tool is currently advertised to every token.

- [ ] **Step 3: Add the scope declaration to the base class**

In `app/mcp/mcp_tool.rb`, inside `class << self`, above the `private` keyword:

```ruby
    # Which OAuth scope a tool needs. Read is the default because it is the safe
    # one: a tool added later without thinking about scopes stays read-only
    # rather than silently escaping the write restriction.
    def required_scope(scope = nil)
      @required_scope = scope if scope
      @required_scope || "mcp:read"
    end

    # Tools a token may use. A nil scope list means the legacy static token,
    # which predates scopes entirely and keeps full access for its deprecation
    # window.
    def permitted_for(tools, scopes)
      return tools if scopes.nil?

      tools.select { |tool| scopes.include?(tool.required_scope) }
    end
```

- [ ] **Step 4: Declare the write scope on the six write tools**

Add this line directly under the `description` line in each of `add_card_to_collection_tool.rb`, `set_collection_quantity_tool.rb`, `add_card_to_deck_tool.rb`, `set_deck_card_owned_copies_tool.rb`, `reallocate_owned_copies_tool.rb` and `set_deck_card_quantity_tool.rb`:

```ruby
  required_scope "mcp:write"
```

- [ ] **Step 5: Filter the tool list in the controller**

In `app/controllers/mcp/server_controller.rb`, inside `handle`, replace `tools: TOOLS` with:

```ruby
        tools: McpTool.permitted_for(TOOLS, @current_scopes),
```

and add above the method:

```ruby
    # Scopes are enforced by what the server is even told about. A tool absent
    # from this list is absent from tools/list and unroutable by tools/call, so a
    # client that guesses a name gets "tool not found" rather than a refusal.
    #
    # This is a deliberate departure from the specification's step-up flow, which
    # expects a 403 insufficient_scope. Producing that would mean parsing the
    # JSON-RPC body here to learn which tool was called, duplicating the dispatch
    # the mcp gem owns. The client learns the same thing at tools/list instead —
    # earlier, and without us reimplementing the protocol. See the design spec.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/integration/mcp_scope_test.rb test/integration/mcp_server_test.rb`
Expected: 0 failures.

- [ ] **Step 7: Sabotage-verify**

- Make `required_scope` default to `"mcp:write"` → the read-only list test must go red.
- Make `permitted_for` return `tools` unconditionally → the read-only tests must go red.
- Remove `required_scope "mcp:write"` from `add_card_to_deck_tool.rb` only → the read-only list test must go red naming exactly that tool. This proves the test checks every write tool, not just the first.

- [ ] **Step 8: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/mcp app/controllers/mcp/server_controller.rb test/integration/mcp_scope_test.rb
git commit -m "feat: gate MCP write tools behind the mcp:write scope"
```

---

### Task 9: Connected applications in /settings

**Files:**
- Create: `app/views/components/settings/connected_apps_section.rb`
- Create: `app/controllers/connected_apps_controller.rb`
- Modify: `app/views/components/settings/show_view.rb`
- Modify: `app/views/components/settings/mcp_token_section.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/connected_apps_controller_test.rb`

**Interfaces:**
- Consumes: `Doorkeeper::AccessToken` (Task 1).
- Produces: nothing other code reads.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/connected_apps_controller_test.rb`:

```ruby
require "test_helper"

class ConnectedAppsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @other = users(:two)
    @application = Doorkeeper::Application.create!(
      name: "Claude",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    sign_in @user
  end

  def token_for(user, scopes: "mcp:read mcp:write")
    Doorkeeper::AccessToken.create!(
      application: @application, resource_owner_id: user.id, scopes: scopes
    )
  end

  test "settings lists the user's connected applications and their scopes" do
    token_for(@user)

    get settings_path

    assert_response :success
    assert_select "[data-testid='connected-app']", count: 1
    assert_select "[data-testid='connected-app']", text: /Claude/
  end

  test "settings does not list another user's connections" do
    token_for(@other)

    get settings_path

    assert_select "[data-testid='connected-app']", count: 0
  end

  test "revoking a connection kills its tokens" do
    token = token_for(@user)

    delete connected_app_path(@application)

    assert_redirected_to settings_path
    assert token.reload.revoked?
  end

  test "revoking cannot touch another user's tokens" do
    mine = token_for(@user)
    theirs = token_for(@other)

    delete connected_app_path(@application)

    assert mine.reload.revoked?
    assert_not theirs.reload.revoked?
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/connected_apps_controller_test.rb`
Expected: FAIL — `undefined local variable or method 'connected_app_path'`.

- [ ] **Step 3: Write the controller**

Create `app/controllers/connected_apps_controller.rb`:

```ruby
# The user-facing half of Doorkeeper's :authorized_applications controller,
# which routes.rb skips. Revocation is scoped to the current user's own tokens:
# an application is shared between users, so revoking it must never reach past
# the person clicking the button.
class ConnectedAppsController < ApplicationController
  def destroy
    current_user_tokens.where(application_id: params[:id]).find_each(&:revoke)

    redirect_to settings_path, notice: "Connection revoked."
  end

  private

  def current_user_tokens
    Doorkeeper::AccessToken.where(resource_owner_id: current_user.id, revoked_at: nil)
  end
end
```

- [ ] **Step 4: Write the Phlex section**

Create `app/views/components/settings/connected_apps_section.rb`:

```ruby
module Settings
  # OAuth clients the user has authorized. One row per application, not per
  # token: a client refreshing its access token would otherwise pile up rows for
  # what the user experiences as a single connection.
  class ConnectedAppsSection < ApplicationComponent
    def initialize(user:)
      @user = user
    end

    def view_template
      section(id: "connected-apps", class: "settings-section") do
        h2 { "Connected applications" }
        p(class: "settings-section-lead") do
          plain "MCP clients you have authorized to reach your collection and decks."
        end
        connections.any? ? list : empty_state
      end
    end

    private

    def connections
      @connections ||= Doorkeeper::AccessToken
        .where(resource_owner_id: @user.id, revoked_at: nil)
        .includes(:application)
        .group_by(&:application)
        .filter_map { |application, tokens| [ application, tokens.min_by(&:created_at) ] if application }
    end

    def empty_state
      p { "None yet." }
    end

    def list
      ul(class: "settings-list") do
        connections.each { |application, first_token| row(application, first_token) }
      end
    end

    def row(application, first_token)
      li(class: "settings-list-item", data: { testid: "connected-app" }) do
        strong { application.name }
        span(class: "settings-list-meta") do
          plain "#{scope_summary(first_token)} — connected #{first_token.created_at.to_date.to_fs(:long)}"
        end
        revoke_button(application)
      end
    end

    def scope_summary(token)
      token.scopes.include?("mcp:write") ? "Read and write" : "Read only"
    end

    def revoke_button(application)
      button_to "Revoke", connected_app_path(application),
        method: :delete, class: "button-secondary",
        form: { data: { turbo_confirm: "Revoke this connection?" } }
    end
  end
end
```

- [ ] **Step 5: Render it and deprecate the token section**

In `app/views/components/settings/show_view.rb`, render `Settings::ConnectedAppsSection.new(user: @user)` directly after the existing `McpTokenSection`. Follow the file's existing rendering idiom.

In `app/views/components/settings/mcp_token_section.rb`, change the lead paragraph to:

```ruby
        p(class: "settings-section-lead") do
          strong { "Deprecated." }
          plain " Connect through an OAuth client instead — most MCP clients do this "
          plain "for you when you give them the server URL. This token still works, "
          plain "and will be removed in a future release."
        end
```

- [ ] **Step 6: Add the route**

Inside the `authenticate :user` block in `config/routes.rb`, next to `resource :mcp_token`:

```ruby
    resources :connected_apps, only: [ :destroy ]
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/connected_apps_controller_test.rb`
Expected: 4 runs, 0 failures.

- [ ] **Step 8: Sabotage-verify**

- Drop the `resource_owner_id` condition in `current_user_tokens` → the cross-user revocation test must go red.
- Drop the same condition in `ConnectedAppsSection#connections` → the "does not list another user's connections" test must go red.

- [ ] **Step 9: Update the styleguide**

`CLAUDE.md` requires `/styleguide` to stay current. Add `Settings::ConnectedAppsSection` to `Styleguide::PageView` alongside the existing `McpTokenSection` sample, using a user with no connections so it renders the empty state without fixtures.

- [ ] **Step 10: Commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add app/controllers/connected_apps_controller.rb app/views/components/settings config/routes.rb test/controllers/connected_apps_controller_test.rb app/views/components/styleguide
git commit -m "feat: list and revoke connected OAuth applications from settings"
```

---

### Task 10: Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-08-14-mcp-oauth-authorization-design.md`

**Interfaces:** none.

- [ ] **Step 1: Update the MCP server paragraph in `CLAUDE.md`**

Replace the sentence describing authentication with a description of both paths: OAuth 2.1 through Doorkeeper as the supported route (dynamic registration, PKCE, `mcp:read`/`mcp:write` scopes, consent at `/oauth/authorize`, connections managed at `/settings`), and the static bearer token as deprecated but still accepted. Mention the two `.well-known` documents and the `WWW-Authenticate` challenge, since they are load-bearing and invisible from the routes file alone.

Add a line to the Bin Scripts section noting that `bin/rails 'mcp:token[…]'` is deprecated alongside the token itself.

- [ ] **Step 2: Record the resolved uncertainties in the spec**

The spec was written before implementation resolved two open questions. Amend it:
- In the consent section, state whether Doorkeeper accepted a narrowed `scope` on the POST directly or whether the `narrow_scopes_to_consent` fallback from Task 6 was needed, so a future reader is not left guessing which mechanism is live.
- In the Doorkeeper configuration table, replace `force_pkce | true` with the exact form the installed version accepted.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-08-14-mcp-oauth-authorization-design.md
git commit -m "docs: describe OAuth authorization for the MCP server"
```

---

### Task 11: Verify against a real Claude web connector

**Files:** none.

This task is manual and is the only proof that matters. Nothing before it demonstrates that Claude's actual client accepts what we built.

- [ ] **Step 1: Deploy**

Run the CI workflow with `workflow_dispatch` as `CLAUDE.md` describes. All four checks must pass before the deploy step runs.

- [ ] **Step 2: Add the connector**

In Claude web, add a custom connector for `https://cartodex.ezveus.eu/mcp`, leaving both advanced fields empty. Expect: a redirect to Cartodex sign-in, then the consent screen, then a connected state.

- [ ] **Step 3: Check what happened server-side**

```bash
ssh cartodex.ezveus.eu 'docker logs --tail 200 $(docker ps --filter name=cartodex-web -q)'
```

Confirm in order: a 401 on `/mcp` carrying the challenge, a 200 on `/.well-known/oauth-protected-resource/mcp`, a 200 on `/.well-known/oauth-authorization-server`, a 201 on `/oauth/register`, then the authorize and token requests, then authenticated `/mcp` calls. A step that never appears is a step Claude did not take — read the metadata document it last fetched before stopping.

- [ ] **Step 4: Exercise both scopes**

Ask Claude to list your decks (read), then to add a card to your collection (write). Then revoke the connection from `/settings` and confirm the next call fails and Claude offers to reconnect.

- [ ] **Step 5: Re-connect with write refused**

Add the connector again, uncheck the write permission, and confirm Claude sees only the six read tools.

- [ ] **Step 6: Report**

Record what worked and what did not. Anything Claude rejected is a spec correction, not a test to loosen.

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: Doorkeeper configuration and tables → 1; routes → 1, 2, 4, 6, 7, 9; metadata documents → 2; `/mcp` authentication and the challenge → 3; rate-limit bump → 3; dynamic registration and the host allowlist → 4; registration throttle → 4; purge → 5; consent screen and scope narrowing → 6; audience validation → 7; scope enforcement and the documented 403 deviation → 8; settings and deprecation notice → 9; docs → 10; rollout verification → 11.

**Known gaps, stated rather than hidden.** Three things in this plan are contingent on behaviour I could not verify without running the code, and each carries its resolution inline rather than a promise to figure it out later: the exact `force_pkce` invocation (Task 1 Step 7), whether Doorkeeper accepts a narrowed scope on the consent POST (Task 6 Step 2, with the fallback code given in full), and whether `Doorkeeper::Application` declares an `access_grants` association (Task 5 Step 3, with the alternative query given). Task 10 Step 2 exists to write the answers back into the spec.

**Type consistency.** `required_scope` returns a String throughout; `@current_scopes` is an Array of Strings or `nil`, produced in Task 3 and consumed only in Task 8; `ResourceIndicator.valid?(value, canonical_uri)` takes the same two arguments at both call sites; `ClientRegistrar::InvalidMetadata#code` is a String matching the RFC 7591 error names rendered by the controller.
