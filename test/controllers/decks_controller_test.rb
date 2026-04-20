require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Original", description: "Desc")
    sign_in @user
  end

  test "edit renders the show page with the edit frame" do
    get edit_deck_path(@deck)

    assert_response :success
    assert_select "turbo-frame#deck-header form"
  end

  test "update with valid params renders the frame in display mode" do
    patch deck_path(@deck), params: { deck: { name: "Renamed", description: "New" } }

    assert_response :success
    assert_select "turbo-frame#deck-header h1", text: "Renamed"
    assert_equal "Renamed", @deck.reload.name
    assert_equal "New", @deck.description
  end

  test "update with invalid params re-renders the form with errors" do
    patch deck_path(@deck), params: { deck: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#deck-header form"
    assert_equal "Original", @deck.reload.name
  end

  test "destroy removes the deck and redirects to index" do
    assert_difference -> { Deck.count }, -1 do
      delete deck_path(@deck)
    end

    assert_redirected_to decks_path
  end

  test "destroy cascades to deck_cards and deck_results" do
    @deck.deck_cards.destroy_all
    @deck.deck_results.destroy_all
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
    @deck.deck_results.create!(result: "win", played_at: Time.current)

    assert_difference [ -> { DeckCard.count }, -> { DeckResult.count } ], -1 do
      delete deck_path(@deck)
    end
  end

  test "duplicate creates a new deck and redirects to it" do
    assert_difference -> { Deck.count }, 1 do
      post duplicate_deck_path(@deck)
    end

    new_deck = Deck.order(:id).last
    assert_redirected_to deck_path(new_deck)
    assert_equal "Copy of Original", new_deck.name
  end

  test "cannot edit another user's deck" do
    get edit_deck_path(decks(:two))

    assert_response :not_found
  end

  test "cannot destroy another user's deck" do
    assert_no_difference -> { Deck.count } do
      delete deck_path(decks(:two))
    end

    assert_response :not_found
  end

  test "cannot duplicate another user's deck" do
    assert_no_difference -> { Deck.count } do
      post duplicate_deck_path(decks(:two))
    end

    assert_response :not_found
  end

  test "tournament_pdf export returns a PDF" do
    profile = tournament_profiles(:ash)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)

    get export_deck_path(@deck, style: "tournament_pdf", profile_id: profile.id)

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert @deck.name.parameterize.present?
    assert_match(/decklist\.pdf/, response.headers["Content-Disposition"])
    assert response.body.start_with?("%PDF")
  end

  test "tournament_pdf export rejects another user's profile" do
    other_profile = tournament_profiles(:giovanni)

    get export_deck_path(@deck, style: "tournament_pdf", profile_id: other_profile.id)

    assert_response :not_found
  end
end
