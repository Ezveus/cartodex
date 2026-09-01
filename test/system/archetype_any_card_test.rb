require "application_system_test_case"

class ArchetypeAnyCardTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
    @deck = @user.decks.create!(name: "Boss Box", physical: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
  end

  # A Trainer-led archetype has no energy type, so its badge falls back to the
  # neutral style rather than a typed one. That fallback already existed; what is
  # new is that an archetype can reach it at all.
  test "a Trainer-led archetype renders with the neutral badge" do
    # custom_name: "1" is required alongside name: — without it, auto_generate_name
    # (unless: :custom_name?) overwrites the name with the primary card's name on
    # create, since custom_name is a transient attr_accessor, not the name: kwarg.
    archetype = Archetype.create!(primary_card: cards(:bosss_orders_meg), name: "Boss Box", custom_name: "1")
    @deck.update!(archetype: archetype)

    visit deck_path(@deck)

    assert_selector ".badge.badge-archetype", text: "Boss Box"
    assert_no_selector ".badge.badge-energy", text: "Boss Box"
  end

  test "the deck's archetype picker offers a Trainer and shows its printing" do
    visit edit_deck_path(@deck)
    click_button "Suggest" if page.has_button?("Suggest")

    find("[data-archetype-picker-target='input']").fill_in with: "Boss"

    find(".archetype-create-item", text: "Create new archetype").click

    within(".create-archetype-section") do
      find("[data-archetype-picker-target='primaryInput']").fill_in with: "Boss's Orders"
      # Both printings must be listed — that's what proves dedup-by-name is gone.
      # Deliberately not asserting which renders first: neither of these two
      # fixtures has an imported set, so `/api/cards`'s release-date ordering
      # cannot separate them and their order rests on fixture ids. The property
      # at stake is that neither printing is collapsed away.
      assert_selector ".archetype-search-item", text: "MEG 114"
      assert_selector ".archetype-search-item", text: "PAL 172"
      assert_selector ".archetype-search-item", count: 2
      find(".archetype-search-item", text: "MEG 114").click
      # The input must name the printing that was picked, not just the card: two
      # printings share this name, and the hidden id now holds one of them — a
      # bare name would not say which, and would read as the whole value on the
      # admin form, where the same input is pre-filled for editing.
      assert_field(with: "Boss's Orders (MEG 114)")
      click_button "Create & select"
    end

    assert_field(with: "Boss's Orders")
  end

  # The other way the create form gets filled. Suggest writes the detector's
  # candidate straight into the input, so it has to name the printing the same
  # way picking from the dropdown does — otherwise the field says one thing
  # before the user touches it and another after.
  test "the Suggest prefill names the printing too" do
    deck = @user.decks.create!(name: "Froakie Box", physical: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:froakie_twm), quantity: 4)

    visit edit_deck_path(deck)
    click_button "Suggest"

    within(".create-archetype-section") do
      assert_field(with: "Froakie (TWM 56)")
    end
  end

  # Task 4 changed the archetype JSON so primary_card/secondary_card are objects
  # ({ id, name, set_name, set_number }) rather than bare names, and
  # archetype_picker_controller.js#formatCard renders "Name (SET NUMBER)" from
  # that object. If the JSON ever reverted to a bare name, formatCard would
  # render "undefined (undefined undefined)" instead — and nothing else in the
  # repo would notice, since the card-search dropdown above builds its own
  # "SET NUMBER" text directly from set_name/set_number rather than going
  # through formatCard.
  test "the archetype search dropdown shows an existing archetype's printing, not just its name" do
    Archetype.create!(primary_card: cards(:bosss_orders_meg), name: "Boss Box", custom_name: "1")

    visit edit_deck_path(@deck)
    find("[data-archetype-picker-target='input']").fill_in with: "Boss"

    assert_selector ".archetype-search-item .archetype-search-pokemon", text: "MEG 114"
  end
end
