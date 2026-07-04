require "test_helper"

class AllocationUiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @card = cards(:budew_pre)
  end

  test "deck show renders real/proxy split and owned_copies stepper on physical decks" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 3)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    get deck_path(deck)

    assert_response :success
    assert_select ".deck-card-alloc", /2 real/
    assert_select "[data-controller~=deck-card-owned-copies]"
  end

  test "deck show flags an over-allocated card" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 1)
    deck = @user.decks.create!(name: "Phys", physical: true)
    # committed 2 > owned 1 → over-allocated
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get deck_path(deck)

    assert_select ".deck-card-warning"
  end

  test "collection tile shows owned/committed/available" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 4)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get collections_path

    assert_response :success
    assert_select ".collection-tile-alloc", /owned 4/
    assert_select ".collection-tile-alloc", /committed 2/
    assert_select ".collection-tile-alloc", /available 2/
  end

  test "over_allocations page lists over-allocated cards and contributing decks" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 1)
    deck = @user.decks.create!(name: "Contrib", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get over_allocations_path

    assert_response :success
    assert_select ".over-allocation-row", 1
    assert_select ".over-allocation-row", /#{@card.name}/
    assert_select ".over-allocation-row", /Contrib/
  end
end
