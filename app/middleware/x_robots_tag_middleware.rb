# Sets X-Robots-Tag on the way out of the whole middleware stack, not merely the app's own
# controllers. Nothing in Cartodex is indexable for now (decision 12 of the design), and a
# header is what also covers what has no <head>: the JSON API and the image proxy.
#
# A Rack middleware, not config.action_dispatch.default_headers: that mechanism only reaches
# responses built through ActionController::Base/API's make_response! (the
# ActionController::DefaultHeaders concern). Warden's own sign-in redirect is built by
# Devise::FailureApp, which subclasses ActionController::Metal directly and never mixes that
# concern in, so default_headers silently leaves it uncovered. Inserted at position 0 in
# config/application.rb, this wraps the entire stack — Warden::Manager included — so it runs
# on every response's way out regardless of what built it.
class XRobotsTagMiddleware
  HEADER_VALUE = "noindex, nofollow".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers["X-Robots-Tag"] ||= HEADER_VALUE
    [ status, headers, body ]
  end
end
