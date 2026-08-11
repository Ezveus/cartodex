require "test_helper"

# The transport's header-hash key casing is not part of its contract — it was
# "Content-Type" up to mcp 0.24 and became "content-type" in 0.25 — so the
# controller has to read it case-insensitively. Every response reachable today
# is JSON, which makes a regression here invisible end-to-end; these exercise
# the lookup directly so the stream case stays covered.
class Mcp::ServerControllerTest < ActiveSupport::TestCase
  def content_type_of(headers)
    Mcp::ServerController.new.send(:content_type_of, headers)
  end

  test "reads the content type whatever the header casing" do
    assert_equal "text/event-stream", content_type_of({ "Content-Type" => "text/event-stream" })
    assert_equal "text/event-stream", content_type_of({ "content-type" => "text/event-stream" })
    assert_equal "text/event-stream", content_type_of({ "CONTENT-TYPE" => "text/event-stream" })
  end

  test "ignores unrelated headers" do
    headers = { "cache-control" => "no-cache", "content-type" => "text/event-stream" }

    assert_equal "text/event-stream", content_type_of(headers)
  end

  test "falls back to JSON when the transport reports no content type" do
    assert_equal "application/json", content_type_of({ "cache-control" => "no-cache" })
    assert_equal "application/json", content_type_of({})
    assert_equal "application/json", content_type_of(nil)
  end
end
