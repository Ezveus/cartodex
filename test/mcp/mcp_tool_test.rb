require "test_helper"

class McpToolTest < ActiveSupport::TestCase
  test "auto-derived tool names strip the _tool suffix" do
    assert_equal "add_card_to_collection", AddCardToCollectionTool.name_value
    assert_equal "search_cards", SearchCardsTool.name_value
  end

  class ExplicitlyNamedTool < McpTool
    tool_name "keep_this_tool"
  end

  test "an explicitly set tool_name is preserved even when it ends in _tool" do
    assert_equal "keep_this_tool", ExplicitlyNamedTool.name_value
  end

  # Mcp::ServerController::TOOLS is named by no other test than McpScopeTest's own WRITE_TOOLS
  # array, which is itself a hand-maintained literal — so a tool file added and forgotten in both
  # is asserted about by nothing and is simply invisible over the wire. Derived from the directory
  # rather than from McpTool.descendants, because eager loading is off in this environment and
  # because ExplicitlyNamedTool above is a descendant that is deliberately not registered.
  test "every tool file in app/mcp is registered on the server" do
    on_disk = Dir[Rails.root.join("app/mcp/*_tool.rb")]
             .map { |path| File.basename(path, ".rb") }
             .reject { |name| name == "mcp_tool" }
             .map { |name| name.camelize.constantize }

    assert_equal [], on_disk - Mcp::ServerController::TOOLS,
      "these tool classes exist but are not in Mcp::ServerController::TOOLS"
  end
end
