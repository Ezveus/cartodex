require "application_system_test_case"

# The whole path an admin takes, in a browser: the button on the set page, the form's real field
# names as Capybara fills them, and the attack reaching the public page, where it is shown.
class AdminCardCreateTest < ApplicationSystemTestCase
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    login_as @admin, scope: :user
  end

  test "an admin creates a Pokémon with an attack from its set's page" do
    visit admin_root_path
    click_nav_link "Card Sets"
    click_link "Perfect Order"
    click_link "New card"

    assert_selector "h1", text: "New card in Perfect Order"
    fill_in "Name", with: "Testmon"
    select "Pokémon", from: "Card type"
    select "Basic", from: "Stage"
    fill_in "HP", with: "90"
    select "Fire", from: "Energy Type"
    fill_in "Retreat cost", with: "1"
    fill_in "Rarity", with: "Common"
    fill_in "Set number", with: "999"
    fill_in "Attack 1 name", with: "Ember"
    fill_in "card_attacks_0_cost", with: "R"
    fill_in "card_attacks_0_damage", with: "30"
    fill_in "card_attacks_0_effect", with: "Discard an Energy from this Pokémon."
    click_button "Create Card"

    assert_text "Card created."
    card = Card.find_by!(set_name: "POR", set_number: "999")
    assert_current_path admin_card_path(card)
    assert_selector "h1", text: "Testmon — POR 999"

    visit card_path(card)
    assert_selector ".card-move", text: "Ember"
    assert_selector ".card-move-damage", text: "30"
    assert_text "Discard an Energy from this Pokémon."
  end
end
