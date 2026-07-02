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
end
