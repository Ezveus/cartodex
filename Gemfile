source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1"
gem "minitest", "~> 6.0"
gem "cgi"
gem "tsort"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Model Context Protocol server (collection/deck tools)
gem "mcp", "~> 1.1"

# OAuth 2.1 authorization server, so MCP clients that cannot send a static
# bearer header (Claude web connectors) can authenticate.
gem "doorkeeper", "~> 5.9"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "mission_control-jobs"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
#
# Commented out: nothing in this app attaches or transforms a blob, and neither
# ruby-vips nor mini_magick was ever added, so variant processing has never been
# functional. Keeping the gem is not merely dead weight — it breaks the boot as
# of Rails 8.1.3.1. That release eagerly requires "image_processing/vips" from
# ActiveStorage::Transformers::Vips (reached because `load_defaults 8.1` sets
# variant_processor = :vips). Without ruby-vips, image_processing raises
# "ImageProcessing::Vips requires the ruby-vips gem", whose CamelCase wording
# matches neither /libvips/ nor /image_processing/ in the rescue filter of
# ActiveStorage's engine.rb, so it re-raises instead of warning. With the gem
# absent the require fails as "cannot load such file -- image_processing/vips",
# which does match, and Rails degrades gracefully.
#
# Uncommenting requires adding ruby-vips (plus the libvips native library in CI
# and the Dockerfile) or setting config.active_storage.variant_processor.
# gem "image_processing", "~> 2.0"

# Authentication
gem "devise"

# Component library
gem "phlex-rails", "~> 2.2"

# API Support
gem "rack-cors"

# PDF generation
gem "prawn", "~> 2.5"
gem "prawn-table", "~> 0.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
