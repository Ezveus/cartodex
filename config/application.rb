require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Needed by name below, before Zeitwerk's autoloader is set up (that happens in an initializer,
# well after this file's class body runs) — a bare constant reference here would raise
# NameError.
require_relative "../app/middleware/x_robots_tag_middleware"

module Cartodex
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Europe/Paris"
    config.autoload_paths << Rails.root.join("app/views/components")

    # Nothing in the app is indexable for now (decision 12 of the design). A header rather than
    # only a meta tag because it also covers what has no <head>: the JSON API and the image
    # proxy. Un-sharing a deck takes it off Cartodex at once and would not take it out of a
    # search engine for weeks.
    #
    # A Rack middleware inserted at the very front of the stack, not
    # config.action_dispatch.default_headers: that mechanism only reaches responses built via
    # ActionController::Base/API's make_response! (the ActionController::DefaultHeaders
    # concern). Warden's own sign-in redirect is built by Devise::FailureApp, which subclasses
    # ActionController::Metal directly and never mixes that concern in, so default_headers
    # silently leaves it uncovered. Position 0 wraps the entire stack, Warden::Manager
    # included, so this runs on the way out regardless of what built the response.
    config.middleware.insert_before 0, XRobotsTagMiddleware

    I18n.available_locales = %i[en]
    I18n.default_locale    = ENV.fetch("LOCALE", "en").to_sym

    uri = URI.parse(ENV.fetch("URL", "http://localhost:3000"))
    config.url = uri
    Rails.application.routes.default_url_options = { protocol: uri.scheme, host: uri.host, port: uri.port }
  end
end
