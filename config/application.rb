require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

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
    # config.eager_load_paths << Rails.root.join("extras")

    I18n.available_locales = %i[en]
    I18n.default_locale    = ENV.fetch("LOCALE", "en").to_sym

    uri = URI.parse(ENV.fetch("URL", "http://localhost:3000"))
    config.url = uri
    Rails.application.routes.default_url_options = { protocol: uri.scheme, host: uri.host, port: uri.port }
  end
end
