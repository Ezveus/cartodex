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
      div(class: "admin-container") do
        section(class: "settings-section") do
          h2 { "Authorize a connection" }
          client_identity
          scope_form
        end
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

    # Both submissions end in a 302 to the client's own origin — that redirect
    # *is* the authorization response. Turbo would submit them with fetch(),
    # which follows a cross-origin redirect only when the final response carries
    # Access-Control-Allow-Origin; an OAuth callback has no reason to and
    # claude.ai does not. Under Turbo both buttons therefore fail in the browser
    # with "blocked by CORS policy" while the server happily issues the grant.
    # Only a native form submit navigates the top-level document to the client.
    NO_TURBO = { turbo: false }.freeze

    def scope_form
      # Distinct ids: a test harvesting "the rendered form" into POST params
      # needs to scope its query to one of these two forms, or it picks up the
      # other form's hidden fields (including method-override's _method=delete)
      # right along with it.
      form_with(url: oauth_authorization_path, method: :post, id: "consent-authorize-form", class: "settings-form", data: NO_TURBO) do
        hidden_fields
        fieldset(class: "form-fieldset") do
          legend(class: "form-label") { "Permissions" }
          requested_scopes.each { |scope| scope_checkbox(scope) }
        end
        div(class: "form-actions") do
          render Ui::Button.new(label: "Authorize", variant: :primary, type: "submit")
        end
      end
      form_with(url: oauth_authorization_path, method: :delete, id: "consent-deny-form", class: "settings-form", data: NO_TURBO) do
        hidden_fields
        div(class: "form-actions") do
          render Ui::Button.new(label: "Deny", variant: :secondary, type: "submit")
        end
      end
    end

    # Everything Doorkeeper needs to rebuild the request, PKCE challenge
    # included. Losing any of these silently downgrades or breaks the flow.
    #
    # String keys, not Symbol: Phlex dasherizes a Symbol used as an attribute
    # *value* the same way it dasherizes Symbol attribute *keys* (see
    # Phlex::SGML::Attributes#generate_attributes) — passing the Symbol :client_id
    # as this `name` attribute's value would silently render name="client-id",
    # a field Doorkeeper's params parsing would never recognise.
    def hidden_fields
      {
        "client_id" => @pre_auth.client.uid,
        "redirect_uri" => @pre_auth.redirect_uri,
        "state" => @pre_auth.state,
        "response_type" => @pre_auth.response_type,
        "code_challenge" => @pre_auth.code_challenge,
        "code_challenge_method" => @pre_auth.code_challenge_method
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

      label(class: "form-check") do
        input(
          type: "checkbox", name: "granted_scopes[]", value: scope,
          checked: true, disabled: required
        )
        plain SCOPE_DESCRIPTIONS.fetch(scope, scope)
      end
      # A disabled checkbox is never submitted, so the required scope needs a
      # hidden mirror or it silently vanishes from the POST.
      input(type: "hidden", name: "granted_scopes[]", value: scope) if required
    end
  end
end
