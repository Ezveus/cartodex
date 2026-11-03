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

  # The fields the browser would send: names and values read off the rendered form, never a
  # hand-built params hash, so a field name the view gets wrong fails here (phlex-architecture).
  def harvest_form
    form = Nokogiri::HTML(response.body).at_css("form.deck-form")
    fields = form.css("input[name], textarea[name], select[name]").each_with_object({}) do |el, values|
      next if %w[submit button].include?(el["type"])

      values[el["name"]] = case el.name
      when "select" then (el.at_css("option[selected]") || el.at_css("option"))&.[]("value").to_s
      when "textarea" then el.text.delete_prefix("\n")
      else el["value"].to_s
      end
    end
    [ form["action"], fields ]
  end

  def submit_form(fills = {})
    action, fields = harvest_form
    fields.merge!(fills.transform_keys(&:to_s))
    verb = fields.delete("_method") || "post"
    send(verb.downcase, action, params: fields)
  end

  NEW_POKEMON = {
    "card[name]" => "Testmon", "card[card_type]" => "Pokémon", "card[hp]" => "90",
    "card[type_symbol]" => "Fire", "card[retreat_cost]" => "1", "card[rarity]" => "Common",
    "card[set_number]" => "999"
  }.freeze

  def settle(card)
    assert Cards::ManualWriter.call(card, attributes: {},
                                          attacks: card.attacks.map { _1.attributes.slice(*%w[name cost damage effect]) },
                                          abilities: card.abilities.map { _1.attributes.slice(*%w[name effect]) })
    travel 1.minute
    card.reload
  end

  test "new pre-fills the set code and offers three attack and two ability slots, no set select" do
    get new_admin_card_set_card_path(card_sets(:por))

    assert_response :success
    assert_select "input[name='card[set_name]']", 0
    assert_select "input#card_set_name[readonly][value='POR']:not([name])"
    assert_select "input[name^='card[attacks]'][name$='[name]']", 3
    (0..2).each { assert_select "input[name='card[attacks][#{_1}][name]']" }
    assert_select "input[name^='card[abilities]'][name$='[name]']", 2
    (0..1).each { assert_select "input[name='card[abilities][#{_1}][name]']" }
    assert_select "select[name='card[card_set_id]']", 0
  end

  test "create through the rendered form files the card in the URL's set, whatever set id is posted" do
    por = card_sets(:por)
    get new_admin_card_set_card_path(por)

    assert_difference "Card.count", 1 do
      submit_form(NEW_POKEMON.merge("card[attacks][0][name]" => "Ember", "card[attacks][0][cost]" => "R",
                                    "card[attacks][0][damage]" => "30", "card[card_set_id]" => card_sets(:asc).id.to_s))
    end

    card = Card.find_by!(set_name: "POR", set_number: "999")
    assert_redirected_to admin_card_path(card)
    assert_equal "Card created.", flash[:notice]
    assert_equal por, card.card_set
    assert_equal "Perfect Order", card.set_full_name
    assert_equal [ [ "Ember", "R", "30", 0 ] ], card.attacks.pluck(:name, :cost, :damage, :position)
  end

  test "a refused create answers 422 with the errors and what was typed, and writes nothing" do
    get new_admin_card_set_card_path(card_sets(:por))

    assert_no_difference [ "Card.count", "Attack.count" ] do
      submit_form(NEW_POKEMON.merge("card[hp]" => "", "card[attacks][0][name]" => "Ember",
                                    "card[attacks][0][damage]" => "30"))
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_select "input[name='card[attacks][0][name]'][value='Ember']"
    assert_select "input[name='card[attacks][0][damage]'][value='30']"
    assert_select "input[name='card[name]'][value='Testmon']"
  end

  test "a nameless attack slot is refused by its number and re-rendered where it was typed" do
    get new_admin_card_set_card_path(card_sets(:por))

    assert_no_difference "Card.count" do
      submit_form(NEW_POKEMON.merge("card[attacks][1][effect]" => "Discard an Energy."))
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors li", text: "Attack 2 needs a name"
    assert_select "textarea[name='card[attacks][1][effect]']", text: "Discard an Energy."
    assert_select "input[name='card[attacks][0][name]']:not([value]), input[name='card[attacks][0][name]'][value='']"
    assert_select "textarea[name='card[attacks][0][effect]']", text: ""
  end

  test "an update whose fingerprint moved names both resync tasks" do
    card = settle(cards(:honedge))
    old_fingerprint = card.fingerprint

    get edit_admin_card_path(card)
    submit_form("card[hp]" => "80")

    new_fingerprint = card.reload.fingerprint
    assert_not_equal old_fingerprint, new_fingerprint
    assert_equal "Card updated. Its fingerprint moved from #{old_fingerprint} to #{new_fingerprint}: " \
                 "run bin/rails card_labels:resync_fingerprints and bin/rails archetypes:resync_fingerprints.",
                 flash[:notice]
  end

  test "an update leaving the fingerprint alone says only that the card was updated" do
    card = settle(cards(:honedge))

    get edit_admin_card_path(card)
    submit_form("card[rarity]" => "Rare")

    assert_equal "Rare", card.reload.rarity
    assert_equal "Card updated.", flash[:notice]
  end

  test "an update round-trip through the form keeps the attack text and moves updated_at" do
    card = settle(cards(:honedge))
    fingerprint, updated_at = card.fingerprint, card.updated_at

    get edit_admin_card_path(card)
    submit_form("card[attacks][0][effect]" => "Flip a coin.")

    card.reload
    assert_equal fingerprint, card.fingerprint
    assert_operator card.updated_at, :>, updated_at
    assert_equal [ [ "Cut", "C", "10", "Flip a coin." ] ], card.attacks.pluck(:name, :cost, :damage, :effect)
  end

  test "an update fingerprints from the attacks it was given" do
    card = settle(cards(:honedge))

    get edit_admin_card_path(card)
    submit_form("card[attacks][0][name]" => "Slash", "card[attacks][0][cost]" => "MC",
                "card[attacks][0][damage]" => "40")

    reference = Card.new(card.attributes.slice(*%w[name card_type hp type_symbol retreat_cost rarity])
                             .merge("set_name" => "REF", "set_number" => "1"))
    reference.attacks.build(name: "Slash", cost: "MC", damage: "40", position: 0)
    reference.save!
    assert_equal reference.fingerprint, card.reload.fingerprint
  end

  test "editing a card holding four attacks shows four slots and keeps all four" do
    card = cards(:honedge)
    %w[Two Three Four].each.with_index(1) { |name, position| card.attacks.create!(name:, cost: "C", position:) }

    get edit_admin_card_path(card)
    assert_select "input[name^='card[attacks]'][name$='[name]']", 4
    submit_form

    assert_redirected_to admin_card_path(card)
    assert_equal %w[Cut Two Three Four], card.reload.attacks.pluck(:name)
  end

  test "a card with one attack shows it first and two empty slots after it" do
    get edit_admin_card_path(cards(:honedge))

    names = css_select("input[name^='card[attacks]'][name$='[name]']")
    assert_equal 3, names.size
    assert_equal [ "Cut", "", "" ], names.map { _1["value"].to_s }
  end

  test "an edit round-trip keeps one ability, and shows and keeps three" do
    card = cards(:honedge)
    card.abilities.create!(name: "Keen Edge", effect: "Sharp.", position: 0)

    get edit_admin_card_path(card)
    submit_form
    assert_equal [ [ "Keen Edge", "Sharp." ] ], card.reload.abilities.pluck(:name, :effect)

    card.abilities.create!(name: "Second", position: 1)
    card.abilities.create!(name: "Third", position: 2)
    get edit_admin_card_path(card)
    assert_select "input[name='card[abilities][2][name]'][value='Third']"
    submit_form
    assert_equal [ "Keen Edge", "Second", "Third" ], card.reload.abilities.pluck(:name)
  end

  test "an edited card whose stage is outside the list keeps it selected" do
    card = cards(:honedge)
    card.update_column(:stage, "LEGEND")

    get edit_admin_card_path(card)

    assert_select "select[name='card[stage]'] option[selected][value='LEGEND']"
    submit_form
    assert_equal "LEGEND", card.reload.stage
  end

  test "slots are read in the order of their integer keys, not their string order" do
    card = cards(:honedge)

    patch admin_card_path(card), params: { card: { attacks: { "10" => { name: "B" }, "2" => { name: "A" } } } }

    assert_redirected_to admin_card_path(card)
    assert_equal [ [ "A", 0 ], [ "B", 1 ] ], card.reload.attacks.pluck(:name, :position)
  end

  test "create writes every permitted field the form offers" do
    get new_admin_card_set_card_path(card_sets(:por))
    submit_form(NEW_POKEMON.merge(
      "card[stage]" => "Stage 1", "card[subtype]" => "Item", "card[evolves_from]" => "Ember Pup",
      "card[weakness]" => "Water", "card[resistance]" => "Grass", "card[regulation_mark]" => "H",
      "card[artist]" => "Ken Sugimori",
      "card[image_url]" => "https://example.com/testmon.png", "card[effect]" => "Rule text."
    ))

    card = Card.find_by!(set_name: "POR", set_number: "999")
    expected = {
      "name" => "Testmon", "card_type" => "Pokémon", "hp" => 90, "type_symbol" => "Fire", "retreat_cost" => 1,
      "rarity" => "Common", "stage" => "Stage 1", "subtype" => "Item", "evolves_from" => "Ember Pup",
      "weakness" => "Water", "resistance" => "Grass", "regulation_mark" => "H", "artist" => "Ken Sugimori",
      "image_url" => "https://example.com/testmon.png", "effect" => "Rule text."
    }
    assert_equal expected, card.attributes.slice(*expected.keys)
  end

  test "edit writes the fields the old form did not offer" do
    card = cards(:honedge)

    get edit_admin_card_path(card)
    submit_form("card[evolves_from]" => "Nothing", "card[weakness]" => "Water",
                "card[regulation_mark]" => "J", "card[effect]" => "Rule text.")

    card.reload
    assert_equal [ "Nothing", "Water", "J", "Rule text." ],
                 [ card.evolves_from, card.weakness, card.regulation_mark, card.effect ]
  end

  test "stage and subtype are selects over the constants, the current value selected" do
    get new_admin_card_set_card_path(card_sets(:por))
    assert_equal [ "" ] + Card::STAGES, css_select("select[name='card[stage]'] option").map { _1["value"].to_s }
    assert_equal [ "" ] + Card::SUBTYPES, css_select("select[name='card[subtype]'] option").map { _1["value"].to_s }

    get edit_admin_card_path(cards(:honedge))
    assert_select "select[name='card[stage]'] option[selected]", 1
    assert_select "select[name='card[stage]'] option[selected][value='Basic']"

    @card.update_column(:subtype, "Special Energy")
    get edit_admin_card_path(@card)
    assert_select "select[name='card[subtype]'] option[selected][value='Special Energy']"

    @card.update_column(:subtype, "ACE SPEC")
    get edit_admin_card_path(@card)
    assert_select "select[name='card[subtype]'] option[selected][value='ACE SPEC']"
    assert_select "select[name='card[subtype]'] option[value='ACE SPEC']", 1
  end

  test "edit offers the set select and a PATCH through it moves the card" do
    card = cards(:honedge)

    get edit_admin_card_path(card)
    assert_select "select[name='card[card_set_id]']"
    submit_form("card[card_set_id]" => card_sets(:asc).id.to_s)

    assert_equal card_sets(:asc), card.reload.card_set
  end

  test "the new page titles its set, posts to the nested create and cancels to the set" do
    por = card_sets(:por)
    get new_admin_card_set_card_path(por)

    assert_select "h1", text: "New card in Perfect Order"
    assert_select "form.deck-form[action=?][method=post]", admin_card_set_cards_path(por)
    assert_select "form.deck-form input[name='_method']", 0
    assert_select "form.deck-form input[type=submit][value='Create Card']"
    assert_select "form.deck-form a[href=?]", admin_card_set_path(por), text: "Cancel"
  end

  test "the edit page submits Update Card and cancels to the card" do
    get edit_admin_card_path(@card)

    assert_select "form.deck-form[action=?]", admin_card_path(@card)
    assert_select "form.deck-form input[type=submit][value='Update Card']"
    assert_select "form.deck-form a[href=?]", admin_card_path(@card), text: "Cancel"
  end

  test "the set page leads with a New card button" do
    por = card_sets(:por)
    get admin_card_set_path(por)

    assert_select ".admin-header-actions > :first-child.btn.btn-secondary[href=?]",
                  new_admin_card_set_card_path(por), text: "New card"
  end

  # The set is the page's, its code included: a posted set_name would file the printing under
  # another set's code while card_set_id points at this one.
  test "create stores the page's set code whatever set_name is posted" do
    por = card_sets(:por)
    get new_admin_card_set_card_path(por)
    submit_form(NEW_POKEMON.merge("card[set_name]" => "pal"))

    assert_redirected_to admin_card_path(Card.find_by!(set_name: "POR", set_number: "999"))
    assert_not Card.exists?(set_name: %w[pal PAL], set_number: "999")
  end

  test "edit keeps the set code editable" do
    get edit_admin_card_path(cards(:honedge))

    assert_select "input[name='card[set_name]'][value='POR']"
  end

  test "an update whose old fingerprint other printings still carry says they keep it" do
    card = settle(cards(:honedge))
    old_fingerprint = card.fingerprint
    reprint = Card.new(card.attributes.slice(*%w[name card_type hp type_symbol retreat_cost rarity set_name])
                           .merge("set_number" => "999"))
    reprint.attacks.build(name: "Cut", cost: "C", damage: "10", position: 0)
    reprint.save!
    assert_equal old_fingerprint, reprint.fingerprint, "sanity: the reprint shares the fingerprint"

    get edit_admin_card_path(card)
    submit_form("card[hp]" => "80")

    new_fingerprint = card.reload.fingerprint
    assert_not_equal old_fingerprint, new_fingerprint
    assert_equal "Card updated. Its fingerprint moved from #{old_fingerprint} to #{new_fingerprint}; " \
                 "1 other printing(s) keep #{old_fingerprint}, so its labels and archetypes stay with them.",
                 flash[:notice]
  end

  test "the attack and ability slots sit in form fieldsets" do
    get edit_admin_card_path(cards(:honedge))

    assert_select "fieldset.form-fieldset > legend", text: "Attacks"
    assert_select "fieldset.form-fieldset > legend", text: "Abilities"
    assert_select "fieldset.form-group", 0
  end

  test "a non-numeric slot key is ignored" do
    card = cards(:honedge)

    patch admin_card_path(card), params: { card: { attacks: { "0" => { name: "A" }, "foo" => { name: "X" }, "1" => { name: "B" } } } }

    assert_redirected_to admin_card_path(card)
    assert_equal %w[A B], card.reload.attacks.pluck(:name)
  end

  test "a scalar where slots are expected writes no attack and does not fail" do
    card = cards(:honedge)

    patch admin_card_path(card), params: { card: { attacks: "x" } }
    assert_redirected_to admin_card_path(card)
    assert_empty card.reload.attacks

    patch admin_card_path(card), params: { card: { attacks: { "0" => "x" } } }
    assert_redirected_to admin_card_path(card)
    assert_empty card.reload.attacks
  end

  test "edit offers no set as a blank option, and a card without a set keeps none" do
    card = cards(:honedge)
    card.update_column(:card_set_id, nil)

    get edit_admin_card_path(card)
    assert_select "select[name='card[card_set_id]'] option[value='']", text: "— None —"
    submit_form

    assert_redirected_to admin_card_path(card)
    assert_nil card.reload.card_set_id
  end

  test "retreat cost refuses a negative and the type select is labelled Energy Type" do
    get new_admin_card_set_card_path(card_sets(:por))

    assert_select "input[name='card[retreat_cost]'][min='0']"
    assert_select "label[for='card_type_symbol']", text: "Energy Type"
  end
end
