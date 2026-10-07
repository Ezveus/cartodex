require "test_helper"

class OpensearchControllerTest < ActionDispatch::IntegrationTest
  test "describes the spotlight's search endpoint to a browser, without a session" do
    get opensearch_path

    assert_response :success
    assert_equal "application/opensearchdescription+xml", response.media_type

    doc = Nokogiri::XML(response.body)
    doc.remove_namespaces!
    assert_equal "Cartodex", doc.at("ShortName").text
    url = doc.at("Url")
    assert_equal "text/html", url["type"]
    # Literal braces: Nokogiri must not have escaped the placeholder the browser substitutes.
    assert_equal "http://www.example.com/search?q={searchTerms}", url["template"]
  end

  # Chrome ignores the autodiscovery link anywhere but the site's root.
  test "the root page links the description" do
    get root_path

    assert_response :success
    assert_select "head link[rel=search][type='application/opensearchdescription+xml'][href=?]",
      opensearch_path
  end
end
