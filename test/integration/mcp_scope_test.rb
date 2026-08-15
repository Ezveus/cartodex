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
    set_deck_card_printing
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
