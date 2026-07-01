require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "generates an api_token on create" do
    user = User.create!(email: "token-user@example.com", password: "password123")
    assert user.api_token.present?
  end

  test "regenerate_api_token replaces the token" do
    user = User.create!(email: "regen-user@example.com", password: "password123")
    original = user.api_token
    user.regenerate_api_token
    assert_not_equal original, user.api_token
    assert user.api_token.present?
  end
end
