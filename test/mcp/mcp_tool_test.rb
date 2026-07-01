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
end
