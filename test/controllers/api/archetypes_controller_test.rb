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

  # A present secondary that has never been scraped into a fingerprint resolves to
  # "" via `secondary&.fingerprint.to_s` — the exact signature of "no secondary at
  # all". Without a symmetric guard, this would match archetypes(:ogerpon) (a
  # single-member archetype on this same primary) and silently drop the secondary
  # the user chose, answering 201 with secondary_card: null instead of a 422.
  test "answers 422 for a present secondary that has never been scraped into a fingerprint" do
    assert_no_difference "Archetype.count" do
      post api_archetypes_path, params: {
        primary_card_id: cards(:teal_mask_ogerpon_ex).id,
        secondary_card_id: cards(:trainer_card).id
      }, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "Secondary fingerprint"
  end

  test "still returns the existing single-member archetype when no secondary is given" do
    assert_no_difference "Archetype.count" do
      post api_archetypes_path, params: { primary_card_id: cards(:teal_mask_ogerpon_ex).id }, as: :json
    end

    assert_response :created
    assert_equal archetypes(:ogerpon).id, JSON.parse(response.body)["id"]
  end

  test "answers 404 for an unknown card" do
    post api_archetypes_path, params: { primary_card_id: 0 }, as: :json

    assert_response :not_found
  end

  # The model's uniqueness validation and the unique index are separated by a
  # read-then-write window: two concurrent creates can both pass validation, and
  # the loser takes the index in the face. Simulate that race in one thread by
  # making `build` insert the "winner" archetype as a side effect, then forcing
  # the "loser" record's save! to skip validation (so it does not simply raise
  # RecordInvalid, which is already handled) and hit the real unique index —
  # exactly what a genuinely concurrent second request would do.
  test "resolves a concurrent create by returning the archetype the race winner created" do
    primary = cards(:bosss_orders_meg)
    original_build = Api::ArchetypesController.instance_method(:build)

    Api::ArchetypesController.define_method(:build) do |primary_card, secondary_card|
      winner = Archetype.create!(primary_card: primary_card, secondary_card: secondary_card)
      loser = original_build.bind(self).call(primary_card, secondary_card)
      # Populate name/fingerprints the same way a real save! would (their
      # before_validation callbacks), without keeping the uniqueness check that
      # would otherwise turn this into a RecordInvalid, not the RecordNotUnique
      # a real race produces.
      loser.valid?
      loser.define_singleton_method(:save!) { save(validate: false) }
      loser
    end

    begin
      assert_difference "Archetype.count", 1 do
        post api_archetypes_path, params: { primary_card_id: primary.id }, as: :json
      end
    ensure
      Api::ArchetypesController.define_method(:build, original_build)
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal Archetype.find_by(primary_card: primary).id, json["id"]
  end

  test "the index returns each member's printing, not a bare name" do
    get api_archetypes_path, params: { q: "Ogerpon" }

    assert_response :success
    entry = JSON.parse(response.body).find { |a| a["id"] == archetypes(:ogerpon).id }
    assert_equal "TWM", entry["primary_card"]["set_name"]
    assert_equal "25", entry["primary_card"]["set_number"]
  end
end
