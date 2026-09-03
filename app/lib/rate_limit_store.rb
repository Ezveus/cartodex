# Proxies to Rails.cache at call time (rather than capturing it once at class-load, as the
# `rate_limit` macro's `cache_store` default would), so tests can swap Rails.cache for a real
# store and exercise throttling.
#
# A top-level constant in app/lib rather than a constant on ApplicationController, because
# Mcp::ServerController inherits from ActionController::API and could not reach it there.
module RateLimitStore
  def self.increment(...)
    Rails.cache.increment(...)
  end
end
