require "test_helper"

# The routes for decks, cards, the dashboard and search left the `authenticate :user` block,
# so each of those actions lost one of its two guards. This file is what replaces it: one
# assertion per action, signed out, plus one per action signed in — because a halting
# before_action skips the after_action, so verify_authorized cannot fire on the signed-out
# half at all.
class PublicAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user)
    @card = cards(:honedge)
  end

  test "the public actions answer without a session" do
    @deck.update!(shared: true)

    public_gets.each do |label, path|
      get path
      assert_response :success, "expected #{label} to be public, got #{response.status}"
    end
  end

  test "the owner-only actions send a visitor to sign in" do
    owner_only_gets.each do |label, path|
      get path
      assert_redirected_to new_user_session_path, "expected #{label} to require a session"
    end
  end

  test "every owner-only action authorizes when a session is present" do
    sign_in @user

    # This is the half that can actually catch a missing `authorize`: verify_authorized runs
    # as an after_action, and an after_action does not run when a before_action halted.
    owner_only_gets.each do |label, path|
      get path

      if label == "deck compare"
        # Fewer than two decks resolve for a single id, so #compare redirects rather than
        # rendering — that is #compare authorizing and behaving, not a failure to authorize.
        assert_response :redirect, "expected #{label} to answer for its owner, got #{response.status}"
        assert_redirected_to decks_path
      else
        assert_response :success, "expected #{label} to answer for its owner, got #{response.status}"
      end
    end
  end

  test "the owner-only writes send a visitor to sign in" do
    name_was = @deck.name
    shared_was = @deck.shared

    post decks_path, params: { deck: { name: "x" } }
    assert_redirected_to new_user_session_path

    patch deck_path(@deck), params: { deck: { name: "x" } }
    assert_redirected_to new_user_session_path

    post duplicate_deck_path(@deck)
    assert_redirected_to new_user_session_path

    patch share_deck_path(@deck), params: { shared: "1" }
    assert_redirected_to new_user_session_path

    delete deck_path(@deck)
    assert_redirected_to new_user_session_path

    @deck.reload
    assert_equal name_was, @deck.name
    assert_equal shared_was, @deck.shared
    assert_equal 2, Deck.count
  end

  test "the tournament writes send a visitor to sign in" do
    name_was = tournaments(:one).name

    post tournaments_path, params: { tournament: { name: "x", date: "2026-05-01" } }
    assert_redirected_to new_user_session_path

    patch tournament_path(tournaments(:one)), params: { tournament: { name: "x" } }
    assert_redirected_to new_user_session_path

    delete tournament_path(tournaments(:one))
    assert_redirected_to new_user_session_path

    post tournament_entries_path(tournaments(:one)), params: { tournament_entry: { deck_id: decks(:one).id } }
    assert_redirected_to new_user_session_path

    assert_equal name_was, tournaments(:one).reload.name
    assert_equal 2, Tournament.count
  end

  # An event's existence is public, so this is the opposite answer from a deck's: not the
  # static 404 that hides whether the record exists, but a real 404 for an id that does not
  # exist — and, for one that does, the redirect Stage 1 wrote.
  test "an unknown tournament answers 404 to a visitor" do
    get tournament_path(id: 999_999)

    assert_response :not_found
  end

  test "a visitor is sent to sign in for a private deck and an unknown key alike" do
    get deck_path(@deck)
    assert_redirected_to new_user_session_path
    private_location = response.location

    get "/decks/thiskeydoesnotexist22"
    assert_redirected_to new_user_session_path
    # Still no oracle: the two are one answer, exactly as they were when both were the static
    # 404. What changes is only that the answer is not a dead end.
    assert_equal private_location, response.location

    get export_deck_path(@deck)
    assert_redirected_to new_user_session_path
  end

  test "the owner whose session expired is returned to the deck they asked for" do
    # The regression this replaces: the static 404 carries no navbar, no sign-in link and no
    # return-to, so an owner following their own bookmark had nowhere to go from it.
    get deck_path(@deck)

    assert_equal deck_path(@deck), session["user_return_to"]
  end

  test "an unknown card still answers 404 to a visitor" do
    # CardsController includes the same concern and must NOT do the same thing: nothing in the
    # catalog is private, so "not found" means not found, and sign-in would answer a question
    # nobody asked.
    get "/cards/999999"

    assert_response :not_found
  end

  test "an unknown key, a private deck and a stranger are indistinguishable" do
    sign_in users(:two)
    private_deck = @deck

    get deck_path(private_deck)
    private_body = response.body
    private_status = response.status

    get "/decks/thiskeydoesnotexist22"
    unknown_body = response.body
    unknown_status = response.status

    assert_equal 404, private_status
    assert_equal 404, unknown_status
    # Bodies, not just statuses: the two reach the renderer through different exceptions
    # (Pundit::NotAuthorizedError and ActiveRecord::RecordNotFound), and only rescuing both
    # in one place makes them converge. A 403 on one of them would turn an unguessable key
    # into an existence oracle for private decks.
    assert_equal private_body, unknown_body
  end

  test "no response invites indexing, and robots.txt does not block the directive" do
    @deck.update!(shared: true)

    get deck_path(@deck)
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "meta[name=robots][content=?]", "noindex, nofollow"

    # Warden's own sign-in redirect: authenticate_user! throws before any controller code
    # runs, so a before_action never gets a turn at it — and neither does
    # config.action_dispatch.default_headers, which only reaches responses built through
    # ActionController::Base/API. Devise::FailureApp subclasses ActionController::Metal
    # directly. XRobotsTagMiddleware, wrapping the whole stack, is what covers this.
    get edit_deck_path(@deck)
    assert_redirected_to new_user_session_path
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]

    # The header covers what has no <head> at all: JSON (the export endpoint) and the image
    # proxy.
    sign_in @user
    get export_deck_path(@deck)
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]

    # And robots.txt must NOT disallow: a path a crawler may not fetch is a path whose
    # noindex it never reads, and a URL linked from elsewhere can still surface as a bare
    # result. Blocking the crawl defeats the de-indexing it looks like it reinforces.
    refute_match(/^Disallow:\s*\/\s*$/, Rails.public_path.join("robots.txt").read)
  end

  private

  # Label => path, one entry per action that left the authenticate block. Methods rather than
  # constants because the paths need the fixtures, which a constant cannot see. Last in the
  # file: a `test` declared below `private` would be defined private and never run.
  def public_gets
    {
      "dashboard" => dashboard_path,
      "search" => search_path(q: "ab"),
      "cards index" => cards_path,
      "card show" => card_path(@card),
      "deck show (shared)" => deck_path(@deck),
      "shared decks index" => shared_decks_path,
      "tournament catalog" => tournaments_path,
      "tournament page" => tournament_path(tournaments(:one))
    }
  end

  def owner_only_gets
    {
      "decks index" => decks_path,
      "deck new" => new_deck_path,
      "deck edit" => edit_deck_path(@deck),
      "deck stats" => stats_deck_path(@deck),
      "deck matchups" => matchups_decks_path,
      "deck results" => deck_deck_results_path(@deck),
      "deck compare" => compare_decks_path(ids: [ @deck.key ]),
      "collections" => collections_path,
      "my tournaments" => mine_tournaments_path,
      "new tournament" => new_tournament_path,
      "edit tournament" => edit_tournament_path(tournaments(:one)),
      "tournament entry" => tournament_entry_path(tournaments(:one), tournament_entries(:one)),
      "edit tournament entry" => edit_tournament_entry_path(tournaments(:one), tournament_entries(:one))
    }
  end
end
