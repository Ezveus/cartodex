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
    assert_nil User::TOKEN_LIFETIMES.fetch("never")
  end
end
