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

    test "truncates an over-long client name" do
      # Nobody authenticates to reach this endpoint and client_name is stored
      # verbatim, so it needs a bound. Truncated rather than rejected: an
      # over-long name is a nuisance, not something to fail a client over.
      register(valid_metadata.merge(client_name: "A" * 5_000))

      assert_response :created
      assert_equal ClientRegistrar::MAX_CLIENT_NAME_LENGTH,
        JSON.parse(response.body)["client_name"].length
      assert_equal ClientRegistrar::MAX_CLIENT_NAME_LENGTH,
        Doorkeeper::Application.sole.name.length
    end

    test "requires no authentication" do
      register(valid_metadata)

      assert_response :created
    end

    test "throttles registrations past the per-IP limit" do
      with_real_rate_limit_store do
        RegistrationsController::RATE_LIMIT_TO.times do
          register(valid_metadata)
          assert_response :created
        end

        register(valid_metadata)

        assert_response :too_many_requests
      end
    end

    test "maps a Doorkeeper-level redirect_uri validation failure to the same 400 shape" do
      # ClientRegistrar's own checks already screen out a fragment-carrying
      # redirect_uri (see client_registrar_test.rb) before Doorkeeper's model
      # validation ever runs, so provoking the controller's
      # ActiveRecord::RecordInvalid rescue for real requires simulating the
      # regression it exists to guard against: ClientRegistrar itself failing
      # to catch a bad redirect_uri and handing Doorkeeper::Application.create!
      # something only Doorkeeper's own RedirectUriValidator still rejects.
      ClientRegistrar.define_singleton_method(:call) do |_metadata|
        Doorkeeper::Application.create!(
          name: "Claude",
          redirect_uri: "https://claude.ai/api/mcp/auth_callback#fragment"
        )
      end

      register(valid_metadata)

      assert_response :bad_request
      assert_equal "invalid_redirect_uri", JSON.parse(response.body)["error"]
      assert_equal 0, Doorkeeper::Application.count
    ensure
      ClientRegistrar.singleton_class.send(:remove_method, :call)
    end

    test "maps a Doorkeeper-level scope validation failure to invalid_client_metadata, not invalid_redirect_uri" do
      # Same simulated-regression approach as the redirect_uri case above, but
      # for scopes_match_configured (enforce_configured_scopes in
      # config/initializers/doorkeeper.rb): the backstop for ClientRegistrar's
      # own scope allowlist. A scope failure has nothing to do with the
      # redirect_uri, so the response must say invalid_client_metadata — the
      # whole point of this fix round is that a broad rescue used to mislabel
      # this as invalid_redirect_uri.
      ClientRegistrar.define_singleton_method(:call) do |_metadata|
        Doorkeeper::Application.create!(
          name: "Claude",
          redirect_uri: "https://claude.ai/api/mcp/auth_callback",
          scopes: "admin"
        )
      end

      register(valid_metadata)

      assert_response :bad_request
      assert_equal "invalid_client_metadata", JSON.parse(response.body)["error"]
      assert_equal 0, Doorkeeper::Application.count
    ensure
      ClientRegistrar.singleton_class.send(:remove_method, :call)
    end

    private

    # Same fix as test/integration/mcp_server_test.rb's helper of the same
    # name: config/environments/test.rb sets :null_store, which makes
    # `rate_limit` a silent no-op, so a real per-request-counting store is
    # needed for the duration of a throttle test. Safe only because tests run
    # in separate forked processes (parallelize in test_helper.rb), not
    # threads sharing one process.
    def with_real_rate_limit_store
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      yield
    ensure
      Rails.cache = original_cache
    end
  end
end
