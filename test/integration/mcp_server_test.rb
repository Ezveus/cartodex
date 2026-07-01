require "test_helper"

class McpServerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.regenerate_api_token
    @user.save!
    @card = cards(:trainer_card)
  end

  def rpc(name, arguments)
    { jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: name, arguments: arguments } }.to_json
  end

  def auth_headers(token: @user.api_token)
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
end
