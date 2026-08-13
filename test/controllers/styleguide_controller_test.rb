require "test_helper"

class StyleguideControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "renders" do
    get styleguide_path

    assert_response :success
  end

  # The page renders the MCP token panel twice. With the panel's ids hardcoded,
  # both copies answered to #mcp-token and to the same #lifetime field, so the
  # second panel's label focused the first panel's select — invalid HTML, on the
  # page that is supposed to be the reference for it.
  test "the two MCP token panels carry distinct ids" do
    get styleguide_path

    assert_response :success
    ids = css_select("section.settings-section").map { |section| section["id"] }

    assert_equal 2, ids.size, "sanity: the styleguide shows both states of the panel"
    assert_equal ids.uniq, ids, "duplicate section ids: #{ids.inspect}"

    field_ids = css_select("select[name=lifetime]").map { |select| select["id"] }

    assert_equal field_ids.uniq, field_ids, "duplicate lifetime field ids: #{field_ids.inspect}"
    assert_equal field_ids.sort, css_select("label[for^=sg-mcp-token]").map { |l| l["for"] }.sort,
      "each label must point at its own panel's select"
  end
end
