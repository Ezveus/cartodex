require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Devise sign-in for system tests. Warden's test mode installs the session
  # server-side, so a test never has to drive the login form — which it could not
  # anyway: the user fixtures carry a literal string in encrypted_password, not a
  # bcrypt hash, so no password would ever authenticate.
  #
  # Including the module turns test mode on; test_reset! drops the logged-in user
  # so it cannot leak into the next test.
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  # This app labels bare inputs with aria-label rather than a <label for>, so
  # without this fill_in "Search decks" cannot find the field. Off by default in
  # Capybara; on here so tests can address inputs the way a screen reader does.
  Capybara.enable_aria_label = true

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end
end
