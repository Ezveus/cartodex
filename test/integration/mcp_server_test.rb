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

  test "rejects a request with an expired token" do
    @user.update_column(:api_token_expires_at, 1.day.ago)

    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers

    assert_response :unauthorized
    assert_nil @user.reload.api_token_last_used_at
  end

  test "rejects a request with no Authorization header" do
    post "/mcp", params: rpc("list_decks", {}), headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "runs a tool call scoped to the authenticated user" do
    assert_nil @user.collections.find_by(card: @card)

    post "/mcp", params: rpc("add_card_to_collection", { card_id: @card.id, quantity: 2 }), headers: auth_headers

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal 2, @user.collections.find_by(card: @card).quantity
  end

  test "does not spend the anonymous per-IP limit on authenticated requests" do
    with_real_rate_limit_store do
      # The user-visible symptom being fixed: a single agent session goes well
      # past IP_RATE_LIMIT_TO calls a minute from one address (importing a
      # decklist card by card is ~60 calls), and must not be cut off by the
      # limiter that exists to throttle anonymous token spam.
      (Mcp::ServerController::IP_RATE_LIMIT_TO + 10).times do
        post_mcp
        assert_response :success
      end
    end
  end

  test "throttles unauthenticated requests before authentication rejects them" do
    with_real_rate_limit_store do
      limit = Mcp::ServerController::IP_RATE_LIMIT_TO

      limit.times do
        post_mcp(token: "not-a-real-token")
        assert_response :unauthorized
      end

      post_mcp(token: "not-a-real-token")

      # If this returns :unauthorized instead of :too_many_requests, the rate
      # limiter is being skipped for unauthenticated requests (i.e. it runs
      # after reject_unauthenticated! halts the callback chain), which means
      # invalid-token spam is never throttled.
      assert_response :too_many_requests
    end
  end

  test "throttles one user past the per-user rate limit" do
    with_real_rate_limit_store do
      limit = Mcp::ServerController::USER_RATE_LIMIT_TO

      limit.times do
        post_mcp
        assert_response :success
      end

      post_mcp

      assert_response :too_many_requests
    end
  end

  test "does not share the per-user quota between two users on one IP" do
    with_real_rate_limit_store do
      other_token = users(:two).regenerate_api_token
      limit = Mcp::ServerController::USER_RATE_LIMIT_TO

      (limit + 1).times { post_mcp }
      assert_response :too_many_requests

      # Same source IP the first user has been hammering, different bearer
      # token. The per-user bucket must be keyed on the authenticated user, so
      # one user burning their quota never locks out another user who happens
      # to share an egress IP (two agents on one machine, or two accounts
      # behind one provider NAT).
      post_mcp(token: other_token)

      assert_response :success
    end
  end

  private

  # RFC 5737 TEST-NET-3. Public-looking on purpose: ActionDispatch::RemoteIp
  # treats loopback and private ranges as trusted proxies, so a private address
  # here would not survive as request.remote_ip. Every request in this file
  # comes from this one address, which is the scenario that matters: the
  # limiters have to tell clients apart by something other than their IP.
  SOURCE_IP = "203.0.113.1"

  def post_mcp(token: @token)
    post "/mcp",
      params: rpc("list_decks", {}),
      headers: auth_headers(token: token),
      env: { "REMOTE_ADDR" => SOURCE_IP }
  end

  # The test environment's cache store is :null_store (config/environments/test.rb),
  # which makes `rate_limit` a no-op. Swap in a real store for the duration of
  # the block so the limiter's `store.increment` calls actually count requests.
  #
  # Safe only because tests run in separate forked processes
  # (parallelize(workers: :number_of_processors) in test_helper.rb) rather than
  # threads within one process; a thread-based test runner would need each
  # thread isolated (e.g. a store keyed per-thread) to avoid cross-test bleed.
  def with_real_rate_limit_store
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    yield
  ensure
    Rails.cache = original_cache
  end
end
