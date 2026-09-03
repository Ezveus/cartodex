require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "regenerate_api_token returns a raw token and stores only its digest" do
    user = User.create!(email: "regen-user@example.com", password: "password123")

    raw = user.regenerate_api_token

    assert raw.present?
    assert_not_equal raw, user.api_token_digest
    assert_equal User.digest_api_token(raw), user.api_token_digest
  end

  test "regenerate_api_token rotates the token on subsequent calls" do
    user = User.create!(email: "regen-user-2@example.com", password: "password123")

    first_raw = user.regenerate_api_token
    first_digest = user.api_token_digest
    second_raw = user.regenerate_api_token

    assert_not_equal first_raw, second_raw
    assert_not_equal first_digest, user.api_token_digest
  end

  test "authenticate_api_token finds the user matching the raw token" do
    user = User.create!(email: "auth-user@example.com", password: "password123")
    raw = user.regenerate_api_token

    assert_equal user, User.authenticate_api_token(raw)
  end

  test "authenticate_api_token returns nil for a wrong token" do
    user = User.create!(email: "auth-user-2@example.com", password: "password123")
    user.regenerate_api_token

    assert_nil User.authenticate_api_token("wrong")
  end

  test "authenticate_api_token returns nil for blank input" do
    assert_nil User.authenticate_api_token(nil)
    assert_nil User.authenticate_api_token("")
  end

  test "regenerate_api_token stamps created_at and a 90-day expiry by default" do
    user = User.create!(email: "lifetime-default@example.com", password: "password123")

    user.regenerate_api_token

    assert_not_nil user.api_token_created_at
    assert_in_delta 90.days.from_now.to_i, user.api_token_expires_at.to_i, 60
  end

  test "regenerate_api_token with a nil lifetime never expires" do
    user = User.create!(email: "lifetime-never@example.com", password: "password123")

    user.regenerate_api_token(expires_in: nil)

    assert_nil user.api_token_expires_at
    assert_not user.api_token_expired?
  end

  test "authenticate_api_token rejects an expired token" do
    user = User.create!(email: "expired@example.com", password: "password123")
    raw = user.regenerate_api_token
    user.update_column(:api_token_expires_at, 1.day.ago)

    assert_nil User.authenticate_api_token(raw)
  end

  test "authenticate_api_token accepts a token whose expiry is still ahead" do
    user = User.create!(email: "unexpired@example.com", password: "password123")
    raw = user.regenerate_api_token(expires_in: 30.days)

    assert_equal user, User.authenticate_api_token(raw)
  end

  test "authenticate_api_token accepts a token with no expiry" do
    user = User.create!(email: "no-expiry@example.com", password: "password123")
    raw = user.regenerate_api_token(expires_in: nil)

    assert_equal user, User.authenticate_api_token(raw)
  end

  test "revoke_api_token! leaves the user with no token at all" do
    user = User.create!(email: "revoke@example.com", password: "password123")
    raw = user.regenerate_api_token
    user.update_column(:api_token_last_used_at, Time.current)

    user.revoke_api_token!

    assert_nil User.authenticate_api_token(raw)
    assert_not user.api_token?
    assert_nil user.api_token_digest
    assert_nil user.api_token_created_at
    assert_nil user.api_token_expires_at
    assert_nil user.api_token_last_used_at
  end

  test "TOKEN_LIFETIMES is the single source of the default lifetime" do
    assert_equal 90.days, User::TOKEN_LIFETIMES.fetch(User::DEFAULT_LIFETIME_KEY)
    assert_equal 30.days, User::TOKEN_LIFETIMES.fetch("30d")
    assert_equal 1.year, User::TOKEN_LIFETIMES.fetch("1y")
    assert_nil User::TOKEN_LIFETIMES.fetch("never")
  end

  test "authenticate_api_token records the first use" do
    user = User.create!(email: "usage-first@example.com", password: "password123")
    raw = user.regenerate_api_token

    assert_nil user.api_token_last_used_at

    User.authenticate_api_token(raw)

    assert_not_nil user.reload.api_token_last_used_at
  end

  test "authenticate_api_token does not write again within the throttle interval" do
    user = User.create!(email: "usage-throttled@example.com", password: "password123")
    raw = user.regenerate_api_token

    User.authenticate_api_token(raw)
    first = user.reload.api_token_last_used_at

    travel 30.minutes do
      User.authenticate_api_token(raw)
    end

    assert_equal first.to_i, user.reload.api_token_last_used_at.to_i
  end

  test "authenticate_api_token writes again once the throttle interval has passed" do
    user = User.create!(email: "usage-refreshed@example.com", password: "password123")
    raw = user.regenerate_api_token

    User.authenticate_api_token(raw)
    first = user.reload.api_token_last_used_at

    travel 2.hours do
      User.authenticate_api_token(raw)
    end

    assert_operator user.reload.api_token_last_used_at, :>, first
  end

  test "touch_api_token_usage swallows a write-lock timeout rather than failing the caller" do
    user = User.create!(email: "usage-timeout@example.com", password: "password123")
    user.regenerate_api_token
    user.define_singleton_method(:update_column) { |*| raise ActiveRecord::StatementTimeout, "database is locked" }

    assert_nothing_raised { user.touch_api_token_usage }
  end

  # StatementTimeout is only the busy case. A full disk and a read-only mount
  # reach the app as bare StatementInvalid, and the MCP auth path is otherwise
  # read-only: a tool call that only needed to read must not 500 because the
  # telemetry stamp could not be written.
  test "touch_api_token_usage swallows every write failure, not just the busy one" do
    user = User.create!(email: "usage-unwritable@example.com", password: "password123")
    user.regenerate_api_token

    [ "database or disk is full", "attempt to write a readonly database" ].each do |message|
      user.define_singleton_method(:update_column) { |*| raise ActiveRecord::StatementInvalid, message }

      assert_nothing_raised { user.touch_api_token_usage }
    end
  end

  test "touch_api_token_usage leaves the connection's busy_timeout as it found it" do
    user = User.create!(email: "usage-pragma@example.com", password: "password123")
    user.regenerate_api_token
    before = ActiveRecord::Base.connection.query_value("PRAGMA busy_timeout")

    user.touch_api_token_usage

    assert_not_nil user.reload.api_token_last_used_at, "sanity: the stamp must have been written"
    assert_equal before, ActiveRecord::Base.connection.query_value("PRAGMA busy_timeout")
  end

  test "touch_api_token_usage restores busy_timeout even when the write fails" do
    user = User.create!(email: "usage-pragma-failure@example.com", password: "password123")
    user.regenerate_api_token
    user.define_singleton_method(:update_column) { |*| raise ActiveRecord::StatementInvalid, "database is locked" }
    before = ActiveRecord::Base.connection.query_value("PRAGMA busy_timeout")

    user.touch_api_token_usage

    assert_equal before, ActiveRecord::Base.connection.query_value("PRAGMA busy_timeout")
  end

  test "lifetime_for resolves known keys and falls back to the default" do
    assert_equal 30.days, User.lifetime_for("30d")
    assert_equal 1.year, User.lifetime_for("1y")
    assert_nil User.lifetime_for("never"), "never is a known key whose value is nil, not a miss"
    assert_equal 90.days, User.lifetime_for("bogus")
    assert_equal 90.days, User.lifetime_for(nil)
  end

  test "lifetime_key? tells a known key from an unknown one" do
    assert User.lifetime_key?("30d")
    assert User.lifetime_key?("never")
    assert_not User.lifetime_key?("bogus")
    assert_not User.lifetime_key?(nil)
  end

  test "api_token_lifetime_key reports the lifetime the token was issued with" do
    user = User.create!(email: "lifetime-key@example.com", password: "password123")

    assert_equal User::DEFAULT_LIFETIME_KEY, user.api_token_lifetime_key, "no token yet"

    { "30d" => 30.days, "90d" => 90.days, "1y" => 1.year, "never" => nil }.each do |key, duration|
      user.regenerate_api_token(expires_in: duration)

      assert_equal key, user.api_token_lifetime_key
    end
  end

  test "api_token_lifetime_key falls back to the default for a span matching no option" do
    user = User.create!(email: "lifetime-key-odd@example.com", password: "password123")
    user.regenerate_api_token(expires_in: 7.days)

    assert_equal User::DEFAULT_LIFETIME_KEY, user.api_token_lifetime_key
  end

  test "api_token_lifetime_key falls back to the default for a legacy token with no created_at" do
    user = User.create!(email: "lifetime-key-legacy@example.com", password: "password123")
    user.regenerate_api_token(expires_in: 30.days)
    user.update_column(:api_token_created_at, nil)

    assert_equal User::DEFAULT_LIFETIME_KEY, user.reload.api_token_lifetime_key
  end

  # TournamentProfile refuses dependent: :destroy while a participation still points at it
  # (Finding 1's fix), and Devise's "Cancel my account" reaches this same #destroy — so a
  # profile in use could plausibly 500 the whole flow. It doesn't: `has_many :decks,
  # dependent: :destroy` above (line 9, ahead of both tournament associations) always
  # destroys this user's decks first, and Deck's own `has_many :tournament_entries,
  # dependent: :destroy` (deck.rb) empties every entry that deck backs before either
  # tournament_profiles or tournament_entries here gets a callback — every entry has a deck
  # (NOT NULL) belonging to the same user (deck_belongs_to_user), so none can survive its
  # owner's decks. By the time tournament_profiles runs, restrict_with_error never finds
  # anything to refuse. This is what actually protects the flow, not the relative order of
  # the two tournament associations — moving :decks below them, or taking :destroy off
  # Deck#tournament_entries, is what should turn this test red.
  test "cancelling the account removes the user, their entries and their profiles together" do
    user = User.create!(email: "cancelling@example.com", password: "password123")
    deck = Deck.create!(user: user, name: "Farewell Deck", standard_pool: standard_pools(:twm_por))
    profile = user.tournament_profiles.create!(
      player_name: "Departing Player", player_id: "9000001", date_of_birth: Date.new(2000, 1, 1)
    )
    entry = user.tournament_entries.create!(
      tournament: tournaments(:one), deck: deck, tournament_profile: profile
    )

    assert user.destroy, user.errors.full_messages.to_sentence

    assert_not User.exists?(user.id)
    assert_not TournamentEntry.exists?(entry.id)
    assert_not TournamentProfile.exists?(profile.id)
  end

  test "an expired token records no usage" do
    user = User.create!(email: "usage-expired@example.com", password: "password123")
    raw = user.regenerate_api_token
    user.update_column(:api_token_expires_at, 1.day.ago)

    User.authenticate_api_token(raw)

    assert_nil user.reload.api_token_last_used_at
  end
end
