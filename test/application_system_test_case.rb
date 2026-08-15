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

  # The test environment turns forgery protection off, and `csrf_meta_tags` then renders nothing —
  # so `requestJson` reads `.content` off a null meta tag, throws, and reports every write as "the
  # request didn't reach the server". Silent, and fatal to any system test that clicks something
  # which writes. Request tests keep the relaxed setting; only a real browser needs the token.
  setup { ActionController::Base.allow_forgery_protection = true }
  teardown { ActionController::Base.allow_forgery_protection = false }

  # This app labels bare inputs with aria-label rather than a <label for>, so
  # without this fill_in "Search decks" cannot find the field. Off by default in
  # Capybara; on here so tests can address inputs the way a screen reader does.
  Capybara.enable_aria_label = true

  served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"] if ENV["CAPYBARA_SERVER_PORT"]

  # The viewport a test class runs at, for the classes that test something specific to a narrow
  # screen. Chrome will not give a window narrower than 500px — not through `screen_size:`, not
  # through `--window-size`, not through `manage.window.resize_to` — so a test that asked for a
  # phone's width silently got 500 and passed on layout the phone never renders. This overrides the
  # viewport through CDP instead, which is not subject to that floor.
  #
  # `mobile: false`: only the width is being emulated here. Touch and a mobile user agent would
  # change how clicks are delivered, and nothing in this app keys off either.
  #
  # CDP is a Chrome-driver extension, so this works on the local driver — which is what CI uses —
  # but not on the remote one the devcontainer talks to (`Remote::Driver` does not include
  # `HasCDP`). Those runs skip with a reason rather than dying on a bare NoMethodError.
  #
  # Widening the whole suite to both viewports is #98.
  def self.drive_at(width, height)
    setup do
      skip "a narrow viewport needs CDP, which the remote driver does not expose (see #98)" unless cdp?

      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride",
        width: width, height: height, deviceScaleFactor: 1, mobile: false
      )
    end

    # The browser is shared by the whole run, so an override left behind would move every later
    # test to a viewport it never asked for.
    teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if cdp? }
  end

  def cdp?
    page.driver.browser.respond_to?(:execute_cdp)
  end

  if ENV["CAPYBARA_SERVER_PORT"]
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end
end
