require "test_helper"

class Admin::CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
    @card = cards(:trainer_card)
  end

  test "edit renders every validated attribute as an input" do
    get edit_admin_card_path(@card)

    assert_response :success
    assert_select "select[name='card[card_type]'] option[value='']"
    Card::CARD_TYPES.each do |type|
      assert_select "select[name='card[card_type]'] option[value=?]", type
    end
    assert_select "select[name='card[type_symbol]'] option[value=?]", "Lightning"
    assert_select "input[name='card[retreat_cost]']"
    assert_select "input[name='card[set_name]']"
    assert_select "input[name='card[set_number]']"
  end

  test "update persists the permitted attributes" do
    patch admin_card_path(@card), params: { card: { rarity: "Ultra Rare" } }

    assert_redirected_to admin_card_path(@card)
    assert_equal "Ultra Rare", @card.reload.rarity
  end

  test "update can switch a Trainer to a Pokémon through the form fields alone" do
    patch admin_card_path(@card), params: {
      card: { card_type: "Pokémon", hp: "120", type_symbol: "Darkness", retreat_cost: "1" }
    }

    assert_redirected_to admin_card_path(@card)
    @card.reload
    assert_equal "Pokémon", @card.card_type
    assert_equal 1, @card.retreat_cost
  end

  test "update renders the validation errors when the card is invalid" do
    patch admin_card_path(@card), params: { card: { name: "" } }

    assert_response :unprocessable_entity
    assert_select ".form-errors li", text: "Name can't be blank"
    assert_equal "Boss's Orders", @card.reload.name
  end

  test "update surfaces the Pokémon-only errors instead of failing silently" do
    patch admin_card_path(@card), params: { card: { card_type: "Pokémon" } }

    assert_response :unprocessable_entity
    assert_select ".form-errors li", text: "Retreat cost can't be blank"
    assert_equal "Trainer", @card.reload.card_type
  end

  test "index treats LIKE metacharacters in the search as literals" do
    get admin_cards_path(q: "budew")

    assert_select ".data-table-cell a", { text: "Budew", minimum: 1 }, "sanity: the unescaped spelling must match"

    get admin_cards_path(q: "b_dew")

    assert_select ".data-table-cell a", { text: "Budew", count: 0 }, "_ must not act as a wildcard"

    get admin_cards_path(q: "bud%w")

    assert_select ".data-table-cell a", { text: "Budew", count: 0 }, "% must not act as a wildcard"
  end

  test "non-admin users cannot reach the edit form" do
    sign_in users(:two)

    get edit_admin_card_path(@card)

    assert_redirected_to root_path
  end
end
