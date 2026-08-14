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
    ids = css_select("section.settings-section[id^='sg-mcp-token']").map { |section| section["id"] }

    assert_equal 2, ids.size, "sanity: the styleguide shows both states of the panel"
    assert_equal ids.uniq, ids, "duplicate section ids: #{ids.inspect}"

    field_ids = css_select("select[name=lifetime]").map { |select| select["id"] }

    assert_equal field_ids.uniq, field_ids, "duplicate lifetime field ids: #{field_ids.inspect}"
    assert_equal field_ids.sort, css_select("label[for^=sg-mcp-token]").map { |l| l["for"] }.sort,
      "each label must point at its own panel's select"
  end

  # General guard, independent of the MCP-token-specific check above: no two
  # elements anywhere on the reference page may share an id. Narrowing the
  # test above to the token panels lost this page-wide coverage; restored here
  # as its own assertion so it isn't accidentally scoped away again.
  test "no element on the styleguide page shares an id with another" do
    get styleguide_path

    assert_response :success
    ids = css_select("[id]").map { |element| element["id"] }

    assert_equal ids.uniq, ids, "duplicate ids on the page: #{ids.tally.select { |_, n| n > 1 }.keys}"
  end

  # The page renders the spotlight input and, separately, an open results panel. Rendering
  # ResultsView for the demo would have put a second turbo-frame#search_results on the page.
  test "the spotlight demo does not duplicate the results frame" do
    get styleguide_path

    assert_response :success
    assert_select "turbo-frame#search_results", count: 1
    ids = css_select("[role=option]").map { |option| option["id"] }

    assert_equal ids.uniq, ids, "duplicate option ids: #{ids.inspect}"
  end
end
