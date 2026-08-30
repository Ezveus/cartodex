require "test_helper"

class Api::ArchetypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "creates an archetype from a Trainer" do
    assert_difference "Archetype.count", 1 do
      post api_archetypes_path, params: { primary_card_id: cards(:bosss_orders_meg).id }, as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "Boss's Orders", json["name"]
    assert_equal "MEG", json["primary_card"]["set_name"]
    assert_nil json["secondary_card"]
  end

  # Identity is the fingerprint pair, so this is the same archetype the fixture
  # already holds. Looking up by card id would miss it, go to save!, and be
  # refused by the unique index — a 500 for what is a no-op.
  test "returns the existing archetype when given another printing of the same card" do
    reprint = cards(:froakie_cri)
    reprint.update_column(:fingerprint, "ogerpon_shared")

    assert_no_difference "Archetype.count" do
      post api_archetypes_path, params: { primary_card_id: reprint.id }, as: :json
    end

    assert_response :created
    assert_equal archetypes(:ogerpon).id, JSON.parse(response.body)["id"]
  end

  test "answers 422 for a card that has never been scraped into a fingerprint" do
    post api_archetypes_path, params: { primary_card_id: cards(:trainer_card).id }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "Primary fingerprint"
  end

  test "answers 404 for an unknown card" do
    post api_archetypes_path, params: { primary_card_id: 0 }, as: :json

    assert_response :not_found
  end

  test "the index returns each member's printing, not a bare name" do
    get api_archetypes_path, params: { q: "Ogerpon" }

    assert_response :success
    entry = JSON.parse(response.body).find { |a| a["id"] == archetypes(:ogerpon).id }
    assert_equal "TWM", entry["primary_card"]["set_name"]
    assert_equal "25", entry["primary_card"]["set_number"]
  end
end
