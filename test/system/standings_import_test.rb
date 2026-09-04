require "application_system_test_case"

# The admin screen that turns a Limitless results page into public standings rows, driven the way
# an admin actually reaches it: through the admin navbar, which below 768px is behind a hamburger.
#
# What only a browser can check here is that the form and the plan are one page — the preview is a
# GET, so the plan comes back with the form still filled in above it, which is what lets an admin
# read "this event has no Standard pool" and narrow the run without retyping anything. A POST would
# have rendered nothing at all (Turbo refuses a non-redirected 200 answering a form POST), and no
# request test can see that.
#
# The results page is stubbed at HttpFetcher, in this process: a system test boots Puma in-process,
# so the singleton the test replaces is the one the server calls. Nothing here leaves the machine.
class StandingsImportTest < ApplicationSystemTestCase
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    login_as @admin, scope: :user

    @archetype = archetypes(:standings_marker)

    @original_http_fetcher_call = HttpFetcher.method(:call)
    html = File.read(Rails.root.join("test/fixtures/files/limitless_deck_results.html"))
    HttpFetcher.define_singleton_method(:call) { |_url| html }
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  test "an admin reaches the screen from the navbar and previews a run" do
    visit admin_root_path

    # Not a plain click: below the breakpoint the nav link is display:none until the hamburger
    # opens the menu, and Capybara will not click what it cannot see.
    click_nav_link "Limitless import"
    assert_current_path new_admin_standings_import_path

    fill_in "Limitless deck id", with: "280"
    select @archetype.name, from: "Archetype"
    fill_in "Only these events (optional)", with: "NAIC"
    click_on "Preview"

    # The event heading, with the (SR) and (JR) halves folded into it: three Limitless headings,
    # one catalog event.
    assert_selector "h3", text: "NAIC 2026, New Orleans"

    # The two derived values a wrong guess makes permanent, both on screen before anything runs.
    assert_text "International Championship"
    assert_selector "[data-label=Division]", text: "senior"
    assert_selector "[data-label=Division]", text: "junior"

    # The filter really filtered: Worlds and Antwerp are on the same page and neither is here.
    assert_no_selector "h3", text: "World Championships 2026"

    # The form is still above the plan, still carrying what produced it — the whole reason the
    # preview is a GET onto the same screen rather than a page of its own.
    assert_field "Limitless deck id", with: "280"
    assert_field "Only these events (optional)", with: "NAIC"

    # Present, and named with the count it will write. Not clicked: enqueuing the run is a
    # different test's job, and this one has nothing to say about what the job does.
    assert_button "Import 4 rows as #{@archetype.name}"
  end

  # A plan with nothing to write offers no button at all. "Regional Antwerp" predates every
  # Standard pool in the fixtures, so its only row is blocked — and an admin who can click a
  # button that writes nothing learns that the button sometimes does nothing, which is the wrong
  # thing to learn about a control that publishes to a catalog every member reads.
  test "an event no Standard pool covers is shown blocked, with no way to run it" do
    visit new_admin_standings_import_path

    fill_in "Limitless deck id", with: "280"
    select @archetype.name, from: "Archetype"
    fill_in "Only these events (optional)", with: "Antwerp"
    click_on "Preview"

    assert_selector ".standings-import-event--blocked"
    assert_text "no Standard pool covers 2024-11-02"
    assert_no_selector "form.standings-import-confirm"
  end
end
