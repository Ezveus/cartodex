require "test_helper"

class McpServerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @token = @user.regenerate_api_token
    @card = cards(:trainer_card)
  end

  def rpc(name, arguments)
    { jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: name, arguments: arguments } }.to_json
  end

  def auth_headers(token: @token)
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream"
    }
  end

  test "rejects a request without a valid token" do
    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers(token: "not-a-real-token")

    assert_response :unauthorized
  end

  test "rejects a request with no Authorization header" do
    post "/mcp", params: rpc("list_decks", {}), headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "runs a tool call scoped to the authenticated user" do
    assert_nil @user.collections.find_by(card: @card)

    post "/mcp", params: rpc("add_card_to_collection", { card_id: @card.id, quantity: 2 }), headers: auth_headers

    assert_response :success
    assert_equal 2, @user.collections.find_by(card: @card).quantity
  end

  test "throttles requests past the configured rate limit" do
    # The test environment's cache store is :null_store (config/environments/test.rb),
    # which makes `rate_limit` a no-op. Swap in a real store for the duration of
    # this test so the limiter's `store.increment` calls actually count requests.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      limit = Mcp::ServerController::RATE_LIMIT_TO

      limit.times do
        post "/mcp", params: rpc("list_decks", {}), headers: auth_headers
        assert_response :success
      end

      post "/mcp", params: rpc("list_decks", {}), headers: auth_headers

      assert_response :too_many_requests
    ensure
      Rails.cache = original_cache
    end
  end
end
