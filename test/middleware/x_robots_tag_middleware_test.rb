require "test_helper"

# Sitting at position 0 of the stack, this middleware also decorates responses nothing in the
# app built: Rack::Files (/robots.txt, /404.html, /assets/*), the routing 404 and
# HostAuthorization's 403. Those hand back a plain Hash, not the case-insensitive
# Rack::Headers an ActionDispatch::Response carries — which is why a controller test cannot
# see the difference between a lowercase key and a mixed-case one, and this unit test can.
class XRobotsTagMiddlewareTest < ActiveSupport::TestCase
  test "writes the header under the lowercase key Rack 3 requires" do
    _status, headers, _body = middleware_over({}).call({})

    assert_equal XRobotsTagMiddleware::HEADER_VALUE, headers["x-robots-tag"]
    # Rack 3's SPEC says header keys must be lowercase. A mixed-case key on a plain Hash
    # ships exactly as written, so spelling it wrong here is a spec violation downstream.
    assert_equal [ "x-robots-tag" ], headers.keys.grep(/x-robots-tag/i)
  end

  test "leaves alone a directive another producer already set" do
    _status, headers, _body = middleware_over({ "x-robots-tag" => "all" }).call({})

    # `||=` can only defer to a value it can find: keyed by the mixed-case name it never
    # saw this one, and set a second, contradictory header beside it.
    assert_equal "all", headers["x-robots-tag"]
    assert_equal [ "x-robots-tag" ], headers.keys.grep(/x-robots-tag/i)
  end

  private

  # A plain Hash, deliberately.
  def middleware_over(headers)
    XRobotsTagMiddleware.new(->(_env) { [ 200, headers.dup, [ "" ] ] })
  end
end
