require "application_system_test_case"
require "active_job/test_helper"

class TournamentStandingsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  setup do
    @user = users(:one)
    @tournament = tournaments(:one)
    login_as @user, scope: :user
  end

  test "a member adds a row to an event's sheet" do
    visit dashboard_path
    click_nav_link "Tournaments"
    click_on @tournament.name

    click_on "Add a standing"
    fill_in "Player name", with: "Brock"
    select "Senior", from: "Division"
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name
    # exact_text: the same search also matches archetypes(:budew_ogerpon), whose *secondary*
    # card is this one's primary — Archetype.search matches on member card names too, so a
    # plain substring match is ambiguous between "Teal Mask Ogerpon ex" and
    # "Budew / Teal Mask Ogerpon ex".
    find(".archetype-search-item strong", text: archetypes(:ogerpon).name, exact_text: true).click
    fill_in "Final placement", with: "4"
    fill_in "Wins", with: "6"
    fill_in "Losses", with: "2"
    fill_in "Ties", with: "1"
    click_on "Create Tournament standing"

    assert_selector "h1", text: @tournament.name
    assert_selector "h3", text: "Senior"
    assert_text "Brock"
    assert_text "6-2-1"
    assert_text "#4"
  end

  # The picker has no deck here, so it has no Suggest button — and the controller must still
  # connect, or searching an archetype does nothing at all.
  test "the standings form's archetype picker works without a deck" do
    visit new_tournament_standing_path(@tournament)

    assert_no_button "Suggest"
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name

    assert_selector ".archetype-search-item", text: archetypes(:ogerpon).name
  end

  test "a member publishes their own participation and the row is marked as theirs" do
    visit tournament_path(@tournament)

    click_on "Publish my participation"

    # Prefilled from the participation: name from the profile, division from the profile's
    # division on the event's date, placement from the entry.
    assert_field "Player name", with: tournament_profiles(:ash).player_name
    assert_field "Final placement", with: tournament_entries(:one).placement.to_s
    # deck(:one), which the participation is recorded against, carries no archetype (fixtures
    # skip callbacks, so nothing auto-tagged it) — the form does not prefill one, and the
    # archetype is required, so the picker has to be driven here or the save 422s.
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name
    find(".archetype-search-item strong", text: archetypes(:ogerpon).name, exact_text: true).click
    click_on "Create Tournament standing"

    # tournament_standings(:ash_masters) already puts "Ash Ketchum" on the sheet once (in
    # Masters, unlinked), and the row this test just created is a second one (in whatever
    # division the profile falls into on the event's date) — a name-only locator is ambiguous
    # between the two, so the match requires the "You" badge that only the new row carries.
    # (A direct TournamentStanding query here would be a mistake for a different reason: the
    # click above returns to Capybara once the click is dispatched, not once the POST the
    # browser sends has been handled by the server, so an un-synchronized query can race the
    # request. within's own polling is what waits for the row to actually exist.)
    within(".data-table-row", text: /#{Regexp.escape(tournament_profiles(:ash).player_name)}.*You/m) do
      assert_text "You"
    end
    assert_no_text "Publish my participation"
  end

  test "a member claims a row somebody else typed, then unlinks it" do
    visit tournament_path(@tournament)

    within(".data-table-row", text: "Giovanni") { click_on "This is me" }
    within(".data-table-row", text: "Giovanni") { assert_text "You" }

    within(".data-table-row", text: "Giovanni") { click_on "Unlink" }
    within(".data-table-row", text: "Giovanni") { assert_no_text "You" }
  end

  test "a member imports a field list onto a row" do
    visit new_tournament_standing_path(@tournament)

    fill_in "Player name", with: "Brock"
    select "Masters", from: "Division"
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name
    find(".archetype-search-item strong", text: archetypes(:ogerpon).name, exact_text: true).click
    fill_in "Decklist (optional)", with: "4 Doublade TWM 62"
    click_on "Create Tournament standing"

    # The row lands before its list does, which is the point: the import runs in the background
    # and the sheet is not held hostage to a scrape.
    assert_text "Brock"
    assert_selector "#importing-standings .importing-item", text: /Brock/
  end

  test "a visitor reads the sheet and is offered no control on it" do
    Warden.test_reset!

    visit tournament_path(@tournament)

    assert_text "Giovanni"
    assert_no_link "Add a standing"
    assert_no_button "This is me"
    assert_no_link "Edit", exact: true
  end

  # Carry-forward from the review of Task 8: Tournaments::StandingListImportJob broadcasts a
  # replacement row over Turbo Streams, and that row's button_to (claim/unclaim, delete) renders
  # with no CSRF authenticity token — it is built outside a request, via
  # ApplicationController.renderer, which has no session to draw one from. It is believed to work
  # because Turbo attaches X-CSRF-Token from the *live page's* own meta tag before submitting, and
  # Rails' verified_request? accepts that header instead of the stale hidden field — but that was
  # a documented belief, not a tested one, until a button on a broadcast-replaced row is actually
  # clicked in a browser.
  #
  # Getting there without a stub: Rails' own ActiveJob::Railtie defaults queue_adapter to :test
  # (not :async) whenever Rails.env.test?, and nothing in this app overrides that — confirmed by
  # log/test.log showing "Enqueued Tournaments::StandingListImportJob ... to Test(default)" for a
  # plain create. The test adapter only records the job; nothing performs it without
  # perform_enqueued_jobs, which ActionDispatch::IntegrationTest (SystemTestCase's own ancestor)
  # pulls in ActiveJob::TestHelper for. Running the job that way is still a real perform, through
  # the app's real broadcaster — config/cable.yml's test adapter is documented by Action Cable
  # itself as "could be used in system tests too", since it is a thin subclass of the real Async
  # pubsub adapter rather than a mock, and broadcasting is independent of which thread enqueued or
  # ran the job. The decklist names a printing already in the database (cards(:doublade), POR 57)
  # so Cards::Fetcher never re-scrapes it and the import needs no network access either.
  test "a member clicks a button on a row a live broadcast just replaced" do
    visit tournament_path(@tournament)

    click_on "Publish my participation"
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name
    find(".archetype-search-item strong", text: archetypes(:ogerpon).name, exact_text: true).click
    fill_in "Decklist (optional)", with: "4 Doublade POR 57"
    click_on "Create Tournament standing"

    # click_on returns once the click is dispatched, not once Turbo's fetch for the form
    # submission has actually reached the server — waiting for the redirect's own flash is what
    # guarantees the create (and therefore the job's enqueue) has really happened before flushing
    # the queue below; a bare perform_enqueued_jobs { click_on ... } races that fetch and finds
    # nothing queued yet.
    assert_text "Standing recorded."

    # This is the subscription that actually matters, and the sleep belongs here, not right
    # after the first visit: every full Turbo Drive visit — the "Publish my participation" GET,
    # then this create's redirect — tears down and rebuilds the layout's own
    # turbo_stream_from(current_user, :notifications) <turbo-cable-stream-source>, so it is the
    # *this* page's WebSocket handshake that has to finish before the job's broadcast is fired,
    # not the very first page load's. Action Cable does not queue a message for a subscriber
    # that connects after it was published, so a broadcast fired too early is simply never
    # delivered, no matter how long something later waits for it — confirmed the hard way: with
    # the sleep only at the top of the test, the job (traced end-to-end via log/test.log —
    # enqueued, performed, and broadcast successfully in under a second) still occasionally left
    # the browser with nothing rendered, because the redirect's fresh subscription hadn't opened
    # yet when the broadcast went out.
    sleep 1.5

    # Even past the flash and the subscription, flushing found nothing to perform on a handful of
    # runs under the full suite's parallel workers (this machine has exactly 8 cores and the
    # suite runs exactly 8 workers, each pairing a Ruby process with its own headless Chrome —
    # real saturation, not a hypothetical) — the enqueue itself can still occasionally lag behind
    # the flash under that contention. Retrying the flush, rather than trusting one attempt, is
    # what makes this reliable there too; the loop exits the moment one attempt actually performs
    # something, so the common, uncontended case pays none of this budget.
    30.times do
      break if perform_enqueued_jobs.positive?

      sleep 0.5
    end

    # The redirect renders the row with no list yet — the import was still in flight until the
    # flush above. Waiting for the "Decklist" link is what proves the click below lands on the
    # row Turbo swapped in over the wire, not the one the redirect originally rendered: only the
    # broadcast can put that link there. can_edit is true on the broadcast (see the job), so
    # "Unlink" is on this row too, since the standing is linked to *this* reader's own
    # participation. wait: generous — this round trip is a real WebSocket delivery, not a page
    # load Capybara already knows to wait for.
    assert_link "Decklist", wait: 5
    click_on "Unlink"

    # Same disambiguation problem test 3 has (tournament_standings(:ash_masters) already puts
    # "Ash Ketchum" on the sheet once, unlinked, with no list) — here the "Decklist" link, which
    # only the row this test built carries, is what the match requires instead of "You". wait:
    # generous again — Unlink's own redirect is a full page navigation, and under the full
    # suite's parallel workers that can outrun Capybara's 2s default just as the broadcast did.
    within(".data-table-row",
      text: /#{Regexp.escape(tournament_profiles(:ash).player_name)}.*Decklist/m, wait: 5) do
      assert_no_text "You"
      # The deck itself is untouched by unlinking the participation — only the claim goes.
      assert_link "Decklist"
    end
  end

  # Carry-forward from the review of Task 1: an ownerless shared deck (a tournament field list)
  # must serve a visitor the public deck page, not the owner's — DecksControllerTest already
  # covers this directly, but nothing exercises it through a standing's own "Decklist" link, which
  # is the one place this feature sends a reader to a deck it does not own.
  test "a visitor follows a standing's decklist link to the public deck page, not the owner's" do
    tournament_standings(:ash_masters).update!(deck: decks(:field_list))
    Warden.test_reset!

    visit tournament_path(@tournament)
    within(".data-table-row", text: "Ash Ketchum") { click_on "Decklist" }

    assert_selector ".deck-card-item"
    assert_no_selector "form.deck-form"
    assert_no_selector ".deck-actions-dropdown"
  end
end
