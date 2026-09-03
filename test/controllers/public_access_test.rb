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
      "shared decks index" => shared_decks_path
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
      "collections" => collections_path
    }
  end
end
