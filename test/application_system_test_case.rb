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

  # The app has exactly one breakpoint, and both sides of it carry behaviour — the CSS media query
  # in three blocks of application.css, and `window.innerWidth <= 768` in card_preview_controller.js.
  # So the suite is run twice, once per side, selected by SYSTEM_TEST_VIEWPORT (see CLAUDE.md).
  BREAKPOINT = 768

  # `screen_size:` sets the browser's *outer window*, and Chrome will not open one narrower than
  # 500px — not through `screen_size:`, not through `--window-size`, not through
  # `manage.window.resize_to`. The mobile pass therefore really renders at 500, not at the 390 asked
  # for here.
  #
  # That is deliberate and sufficient: the sweep decides only which *side* of the breakpoint a test
  # lands on, and 500 is comfortably inside the mobile one. The 390 records the intent, and holds if
  # the floor ever lifts. A test whose assertions depend on the width itself — a layout that breaks
  # at 344 but not at 500 — must say so with `drive_at`, which goes through CDP and escapes the
  # floor. Confirmed on macOS Chrome; the floor's exact value on the CI image is untested, but any
  # value below 768 leaves the sweep correct.
  MOBILE_SCREEN_SIZE = [ 390, 844 ].freeze
  DESKTOP_SCREEN_SIZE = [ 1400, 1400 ].freeze

  # How many times click_nav_link will open the menu before giving up — see the comment there. Each
  # attempt spends Capybara.default_max_wait_time, so this is a multiplier on that budget.
  NAV_ATTEMPTS = 3

  # Which half of the sweep this process is. Unset is the desktop half, so a plain
  # `bin/rails test:system` keeps behaving exactly as it did.
  #
  # An unrecognised value raises rather than falling back, because the failure is otherwise
  # invisible: `SYSTEM_TEST_VIEWPORT=Mobile` would render 1400px, skip every class pinned to a
  # narrow width, and produce output byte-identical to a deliberate desktop run — a green CI job
  # proving nothing, from one typo in a YAML string. This runs at class-definition time (below,
  # through sweep_screen_size), so the typo takes the process down before a single test reports.
  def self.sweep_viewport
    case ENV["SYSTEM_TEST_VIEWPORT"]
    when nil, "", "desktop" then :desktop
    when "mobile" then :mobile
    else raise ArgumentError, "SYSTEM_TEST_VIEWPORT must be \"mobile\" or \"desktop\", got #{ENV["SYSTEM_TEST_VIEWPORT"].inspect}"
    end
  end

  def self.sweep_screen_size
    sweep_viewport == :mobile ? MOBILE_SCREEN_SIZE : DESKTOP_SCREEN_SIZE
  end

  # The viewport a test class runs at, for the classes that test something specific to a given
  # screen width rather than merely to a side of the breakpoint. This overrides the viewport through
  # CDP, which is not subject to the 500px floor described above.
  #
  # `mobile: false`: only the width is being emulated here. Touch and a mobile user agent would
  # change how clicks are delivered, and nothing in this app keys off either.
  #
  # A class that pins its width belongs to the side that width falls on, and skips the other half of
  # the sweep: running it twice at the same pinned width would only report the same result twice.
  #
  # CDP is a Chrome-driver extension, so this works on the local driver — which is what CI uses —
  # but not on the remote one the devcontainer talks to (`Remote::Driver` does not include
  # `HasCDP`). Those runs skip with a reason rather than dying on a bare NoMethodError.
  def self.drive_at(width, height)
    side = width <= BREAKPOINT ? :mobile : :desktop

    setup do
      skip "pinned to #{width}px, which is the #{side} side of the sweep" unless side == self.class.sweep_viewport
      skip "a narrow viewport needs CDP, which the remote driver does not expose" unless cdp?

      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride",
        width: width, height: height, deviceScaleFactor: 1, mobile: false
      )
      @viewport_override = true
    end

    # The browser is shared by the whole run, so an override left behind would move every later test
    # to a viewport it never asked for.
    #
    # Guarded on the setup having actually run: a `skip` raises, but Minitest runs the teardown
    # chain anyway, so without this the clearing call fires on every skipped test — touching
    # page.driver.browser, which starts Chrome for a test that has no use for it. Worse than waste:
    # this callback is registered last and therefore runs *first*, and ActiveSupport abandons the
    # chain on the first exception, so a dead browser here would swallow `Warden.test_reset!` and
    # the `allow_forgery_protection = false` above for the rest of the process.
    teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override }
  end

  def cdp?
    page.driver.browser.respond_to?(:execute_cdp)
  end

  # Click a link in the navbar, from either side of the breakpoint.
  #
  # Above 768px the hamburger is `display: none` and the menu is `display: contents`, so this is a
  # plain click. Below it the menu is `display: none` until the hamburger toggles
  # `.navbar-menu--open` onto it — and Capybara refuses to click what it cannot see, so a direct
  # click on a nav link fails there. Every test navigating through the navbar goes through here
  # rather than discovering that difference one confusing failure at a time.
  #
  # Both navbars are covered: Ui::AppNavbar and Ui::AdminNavbar render the same markup and classes.
  def click_nav_link(label)
    # Wait for a navbar to exist before deciding anything about it. The checks in open_navbar_menu
    # run with wait: 0 — above the breakpoint the toggle is *meant* to be missing, and waiting for
    # it would spend the full Capybara timeout on every call — so the page must have arrived first.
    find(".navbar", visible: :all)

    # Below the breakpoint this is two interactions where the desktop side has one, and Turbo can
    # swap the page between them: a toggle click landing on the outgoing page leaves the incoming
    # page's menu shut, and the link then never becomes visible. Opening is therefore retried until
    # the link is actually clickable, rather than attempted once and assumed to have worked. Without
    # this, any test navigating twice in a row is flaky on the mobile half of the sweep only.
    #
    # Each attempt waits Capybara's own budget rather than a hardcoded second: the scenario this
    # exists for consumes a whole attempt by design, and how long a Turbo navigation takes is a
    # property of the machine, which a number written here cannot know.
    NAV_ATTEMPTS.times do
      begin
        open_navbar_menu

        return find(:link, label, class: "navbar-link", wait: Capybara.default_max_wait_time).click
      rescue Capybara::Ambiguous
        # A subclass of ElementNotFound, so the rescue below would swallow it and report the exact
        # opposite of what happened — "no visible link" for "two links matched". Never retryable.
        raise
      rescue Capybara::ElementNotFound, Selenium::WebDriver::Error::StaleElementReferenceError
        next
      end
    end

    raise Capybara::ElementNotFound, "the navbar never offered a visible #{label.inspect} link"
  end

  if ENV["CAPYBARA_SERVER_PORT"]
    driven_by :selenium, using: :headless_chrome, screen_size: sweep_screen_size, options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: sweep_screen_size
  end

  private

  # A no-op above the breakpoint, where the hamburger is `display: none` and the menu is already
  # laid out. Below it, the menu stays open after a click, so re-clicking the toggle would shut it:
  # opening is conditional on it not being open already.
  def open_navbar_menu
    return unless has_selector?(".navbar-toggle", wait: 0)
    return if has_selector?(".navbar-menu--open", wait: 0)

    find(".navbar-toggle").click
  rescue Selenium::WebDriver::Error::StaleElementReferenceError
    # The page swapped underneath the toggle. The caller's next attempt sees the new one.
    nil
  end
end
