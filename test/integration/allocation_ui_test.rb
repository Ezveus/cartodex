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

  test "deck list shows a to-review badge and banner when over-allocated" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 1)
    deck = @user.decks.create!(name: "Contrib", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get decks_path

    assert_response :success
    assert_select ".badge-warning", /To review/
    assert_select ".over-allocation-banner"
  end

  test "collections page shows the banner when over-allocated" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 1)
    deck = @user.decks.create!(name: "Contrib", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get collections_path

    assert_select ".over-allocation-banner"
  end

  test "no banner when nothing is over-allocated" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 4)
    deck = @user.decks.create!(name: "OK", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get decks_path

    assert_select ".over-allocation-banner", false
  end

  test "reallocate moves a real copy from one physical deck to another" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 1)
    from = @user.decks.create!(name: "From", physical: true)
    from.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
    to = @user.decks.create!(name: "To", physical: true)
    to.deck_cards.create!(card: @card, quantity: 2, owned_copies: 0)

    post reallocate_over_allocations_path, params: {
      from_deck_id: from.id, to_deck_id: to.id, card_id: @card.id, quantity: 1
    }

    assert_redirected_to over_allocations_path
    assert_equal 1, from.deck_cards.find_by(card: @card).owned_copies
    assert_equal 1, to.deck_cards.find_by(card: @card).owned_copies
  end

  test "reallocate with an invalid move redirects with an alert" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 1)
    from = @user.decks.create!(name: "From", physical: true)
    from.deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)
    to = @user.decks.create!(name: "To", physical: true)
    to.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1) # no proxy slot

    post reallocate_over_allocations_path, params: {
      from_deck_id: from.id, to_deck_id: to.id, card_id: @card.id, quantity: 1
    }

    assert_redirected_to over_allocations_path
    assert flash[:alert].present?
  end
end
