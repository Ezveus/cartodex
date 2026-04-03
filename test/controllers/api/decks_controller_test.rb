require "test_helper"

class Api::DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  # --- Import action ---

  test "import enqueues Decks::ImportJob and returns 202" do
    decklist = "4 Honedge POR 56"

    assert_enqueued_with(job: Decks::ImportJob) do
      post import_api_decks_path, params: { name: "My Deck", decklist: decklist }, as: :json
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert json["import_id"].present?, "Response should include an import_id"
  end

  test "import requires authentication" do
    sign_out @user

    post import_api_decks_path, params: { name: "My Deck", decklist: "4 Honedge POR 56" }, as: :json

    assert_response :unauthorized
  end
end
