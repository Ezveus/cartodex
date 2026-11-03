require "test_helper"

class Cards::ManualWriterTest < ActiveSupport::TestCase
  POKEMON = {
    "name" => "Testmon", "card_type" => "Pokémon", "hp" => "90", "type_symbol" => "Fire",
    "retreat_cost" => "1", "rarity" => "Common", "set_name" => "TST", "set_number" => "1"
  }.freeze
  TRAINER = {
    "name" => "Technical Machine: Test", "card_type" => "Trainer", "subtype" => "Tool",
    "rarity" => "Uncommon", "set_name" => "TST", "set_number" => "2"
  }.freeze
  EMBER = { "name" => "Ember", "cost" => "R", "damage" => "30", "effect" => "" }.freeze
  BLANK_ATTACK = { "name" => "", "cost" => "", "damage" => "", "effect" => "" }.freeze
  BLANK_ABILITY = { "name" => "", "effect" => "" }.freeze

  def write(card = Card.new, attributes: {}, attacks: [], abilities: [])
    Cards::ManualWriter.call(card, attributes:, attacks:, abilities:)
  end

  # Fixtures are inserted without callbacks, so their fingerprints are placeholders: a first write
  # makes the fingerprint real, and the minute makes a later `updated_at` distinguishable from it.
  def settled(card)
    assert write(card, attacks: card.attacks.map { _1.attributes.slice(*%w[name cost damage effect]) },
                       abilities: card.abilities.map { _1.attributes.slice(*%w[name effect]) }),
           card.errors.full_messages.to_sentence
    travel 1.minute
    card.reload
  end

  def documented_card(attributes, attacks: [])
    card = Card.new(attributes)
    attacks.each { card.attacks.build(**_1) }
    card.save!
    card
  end

  def with_real_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  test "a Pokémon written from slots fingerprints like the same card built the documented way" do
    card = Card.new
    assert write(card, attributes: POKEMON, attacks: [ EMBER, BLANK_ATTACK, BLANK_ATTACK ])

    reference = documented_card(POKEMON.merge("set_number" => "3"),
                                attacks: [ { name: "Ember", cost: "R", damage: "30", position: 0 } ])
    bare = documented_card(POKEMON.merge("set_number" => "4"))

    assert_equal reference.fingerprint, card.reload.fingerprint
    assert_not_equal bare.fingerprint, card.fingerprint
  end

  test "a named attack with a blank cost is stored as 0, blank damage and effect as nil, all stripped" do
    card = Card.new
    assert write(card, attributes: POKEMON,
                       attacks: [ { "name" => "  Tackle ", "cost" => " ", "damage" => "  ", "effect" => " " },
                                  { "name" => "Ember", "cost" => " R ", "damage" => " 30 ", "effect" => " Burn. " } ])

    assert_equal [ [ "Tackle", "0", nil, nil ], [ "Ember", "R", "30", "Burn." ] ],
                 card.reload.attacks.pluck(:name, :cost, :damage, :effect)
  end

  test "positions count kept slots only" do
    card = Card.new
    assert write(card, attributes: POKEMON, attacks: [ BLANK_ATTACK, EMBER ],
                       abilities: [ BLANK_ABILITY, { "name" => "Blaze", "effect" => "" } ])

    assert_equal [ [ "Ember", 0 ] ], card.reload.attacks.pluck(:name, :position)
    assert_equal [ [ "Blaze", 0 ] ], card.abilities.pluck(:name, :position)
  end

  test "an all-blank slot writes nothing" do
    card = Card.new
    assert write(card, attributes: POKEMON, attacks: [ BLANK_ATTACK ], abilities: [ BLANK_ABILITY ])

    assert_empty card.reload.attacks
    assert_empty card.abilities
  end

  test "a slot with only an effect refuses the card and writes no row at all" do
    card = Card.new

    assert_no_difference [ "Card.count", "Attack.count", "Ability.count" ] do
      assert_not write(card, attributes: POKEMON,
                             attacks: [ BLANK_ATTACK.merge("effect" => "Discard an Energy.") ],
                             abilities: [ { "name" => "Blaze", "effect" => "" } ])
    end
    assert_equal [ "Attack 1 needs a name" ], card.errors[:base]
  end

  test "an update replaces the attacks and abilities" do
    card = cards(:honedge)

    assert write(card, attacks: [ { "name" => "Slash", "cost" => "M", "damage" => "20", "effect" => "" } ],
                       abilities: [ { "name" => "Keen Edge", "effect" => "Sharp." } ])

    assert_equal [ "Slash" ], card.reload.attacks.pluck(:name)
    assert_equal [ [ "Keen Edge", "Sharp." ] ], card.abilities.pluck(:name, :effect)
  end

  test "a refused update leaves the card, its attacks and its abilities exactly as they were" do
    card = cards(:honedge)
    card.abilities.create!(name: "Keen Edge", effect: "Sharp.", position: 0)
    card = settled(card)
    before = [ card.attributes, card.attacks.map(&:attributes), card.abilities.map(&:attributes) ]

    assert_not write(card, attributes: { "hp" => "", "rarity" => "Rare" },
                           attacks: [ { "name" => "Slash", "cost" => "M", "damage" => "", "effect" => "" } ],
                           abilities: [])

    card = Card.find(card.id)
    assert_equal before, [ card.attributes, card.attacks.map(&:attributes), card.abilities.map(&:attributes) ]
  end

  test "a slot-only refusal on an update with valid columns rolls everything back" do
    card = settled(cards(:honedge))
    before = [ card.attributes, card.attacks.map(&:attributes) ]

    assert_not write(card, attributes: { "rarity" => "Rare" },
                           attacks: [ BLANK_ATTACK.merge("effect" => "Orphan text.") ])

    assert_equal [ "Attack 1 needs a name" ], card.errors[:base]
    card = Card.find(card.id)
    assert_equal before, [ card.attributes, card.attacks.map(&:attributes) ]
  end

  test "a Pokémon gets its subtype from its name, a Trainer gets none" do
    ex = Card.new
    assert write(ex, attributes: POKEMON.merge("name" => "Foo ex"))
    assert_equal pokemon_subtypes(:pokemon_ex), ex.reload.pokemon_subtype

    trainer = Card.new
    assert write(trainer, attributes: TRAINER.merge("name" => "Foo ex"))
    assert_nil trainer.reload.pokemon_subtype
  end

  test "the subtype follows a change of type or of name" do
    card = Card.new
    assert write(card, attributes: POKEMON.merge("name" => "Foo ex"))
    assert write(card, attributes: { "card_type" => "Trainer" })
    assert_nil card.reload.pokemon_subtype

    plain = Card.new
    assert write(plain, attributes: POKEMON.merge("name" => "Foo", "set_number" => "9"))
    assert_nil plain.reload.pokemon_subtype
    assert write(plain, attributes: { "name" => "Foo ex" })
    assert_equal pokemon_subtypes(:pokemon_ex), plain.reload.pokemon_subtype
  end

  test "a successful write drops the cached filter values, a refused one leaves them" do
    with_real_cache do
      Rails.cache.write(Card::FILTER_VALUES_CACHE_KEY, "cached")
      assert_not write(Card.new, attributes: POKEMON.merge("hp" => ""))
      assert Rails.cache.exist?(Card::FILTER_VALUES_CACHE_KEY), "a refusal must not drop the cache"

      assert write(Card.new, attributes: POKEMON)
      assert_not Rails.cache.exist?(Card::FILTER_VALUES_CACHE_KEY)
    end
  end

  # Forgetting inside the writer's own transaction would let a concurrent reader refill the cache
  # from rows that are not committed yet.
  test "the cache is forgotten after the writer's transaction has closed" do
    seen = []
    store = ActiveSupport::Cache::MemoryStore.new
    store.define_singleton_method(:delete) do |*args, **options|
      seen << ActiveRecord::Base.connection.open_transactions
      super(*args, **options)
    end
    original, Rails.cache = Rails.cache, store
    outer = ActiveRecord::Base.connection.open_transactions

    assert write(Card.new, attributes: POKEMON)

    assert_equal [ outer ], seen
  ensure
    Rails.cache = original
  end

  test "an update changing only an attack's effect keeps the fingerprint and moves updated_at" do
    card = settled(cards(:honedge))
    fingerprint, updated_at = card.fingerprint, card.updated_at

    assert write(card, attacks: [ { "name" => "Cut", "cost" => "C", "damage" => "10", "effect" => "New text." } ])

    card.reload
    assert_equal fingerprint, card.fingerprint
    assert_operator card.updated_at, :>, updated_at
    assert_equal [ "New text." ], card.attacks.pluck(:effect)
  end

  test "an update fingerprints from the replacement attacks" do
    card = settled(cards(:honedge))
    slash = { "name" => "Slash", "cost" => "MC", "damage" => "40", "effect" => "" }

    assert write(card, attacks: [ slash ])

    reference = documented_card(card.attributes.slice(*%w[name card_type hp type_symbol retreat_cost rarity])
                                    .merge("set_name" => "REF", "set_number" => "1"),
                                attacks: [ { name: "Slash", cost: "MC", damage: "40", position: 0 } ])
    assert_equal reference.fingerprint, card.reload.fingerprint
  end

  test "a Trainer keeps an attack slot" do
    card = Card.new
    assert write(card, attributes: TRAINER, attacks: [ EMBER ])

    assert_equal [ "Ember" ], card.reload.attacks.pluck(:name)
  end

  test "a refusal names the slot by its own number" do
    card = Card.new
    assert_not write(card, attributes: POKEMON,
                           attacks: [ EMBER, BLANK_ATTACK, BLANK_ATTACK.merge("effect" => "Orphan.") ])

    assert_equal [ "Attack 3 needs a name" ], card.errors[:base]
  end

  test "cost-only and damage-only slots are refused, as is a nameless ability" do
    cost_only = Card.new
    assert_not write(cost_only, attributes: POKEMON, attacks: [ BLANK_ATTACK.merge("cost" => "R") ])
    assert_equal [ "Attack 1 needs a name" ], cost_only.errors[:base]

    damage_only = Card.new
    assert_not write(damage_only, attributes: POKEMON, attacks: [ BLANK_ATTACK.merge("damage" => "30") ])
    assert_equal [ "Attack 1 needs a name" ], damage_only.errors[:base]

    ability = Card.new
    assert_not write(ability, attributes: POKEMON,
                              abilities: [ { "name" => "Blaze", "effect" => "" }, { "name" => "", "effect" => "Orphan." } ])
    assert_equal [ "Ability 2 needs a name" ], ability.errors[:base]
  end

  test "a slot of whitespace only is skipped" do
    card = Card.new
    assert write(card, attributes: POKEMON,
                       attacks: [ { "name" => "  ", "cost" => " ", "damage" => "\t", "effect" => "\n" } ],
                       abilities: [ { "name" => " ", "effect" => "  " } ])

    assert_empty card.reload.attacks
    assert_empty card.abilities
  end

  test "column errors and slot errors are reported together" do
    card = Card.new
    assert_not write(card, attributes: POKEMON.merge("hp" => ""), attacks: [ BLANK_ATTACK.merge("effect" => "Orphan.") ])

    assert_includes card.errors.full_messages, "Attack 1 needs a name"
    assert_not_empty card.errors.full_messages_for(:hp)
  end

  BASIC_FIRE = {
    "name" => "Fire Energy", "card_type" => "Energy", "subtype" => "Basic Energy", "type_symbol" => "",
    "stage" => "", "rarity" => "", "artist" => " ", "set_name" => "TST", "set_number" => "5"
  }.freeze

  # Decks::Exporter tells a basic energy by a nil type_symbol: a stored "" exported "Fire Energy".
  test "blank posted fields are stored as nil, so a basic energy exports under its symbol" do
    card = Card.new
    assert write(card, attributes: BASIC_FIRE)

    card.reload
    assert_equal [ nil, nil, nil, nil ], [ card.type_symbol, card.stage, card.rarity, card.artist ]
    deck = decks(:one)
    deck.deck_cards.create!(card:, quantity: 4)
    assert_includes Decks::Exporter.call(deck), "4 Basic {R} Energy TST 5"
  end

  test "a typographic apostrophe is folded and the name stripped, so it fingerprints like the plain one" do
    curly = Card.new
    assert write(curly, attributes: TRAINER.merge("name" => "  Rosa\u2019s Encouragement  "))
    plain = Card.new
    assert write(plain, attributes: TRAINER.merge("name" => "Rosa's Encouragement", "set_number" => "3"))

    assert_equal "Rosa's Encouragement", curly.reload.name
    assert_equal plain.reload.fingerprint, curly.fingerprint
  end

  test "slot values are folded the same way, and a blank ability effect is nil" do
    card = Card.new
    assert write(card, attributes: POKEMON,
                       attacks: [ EMBER.merge("effect" => " Discard your opponent\u2019s Tool. ") ],
                       abilities: [ { "name" => " Rosa\u2019s Blaze ", "effect" => "  " } ])

    assert_equal [ "Discard your opponent's Tool." ], card.reload.attacks.pluck(:effect)
    assert_equal [ [ "Rosa's Blaze", nil ] ], card.abilities.pluck(:name, :effect)
  end

  test "an unchanged edit of a card with nil artist and stage leaves them nil" do
    card = settled(cards(:honedge))
    card.update_columns(artist: nil, stage: nil)

    assert write(card, attributes: { "artist" => "", "stage" => "", "rarity" => "Common" })

    card.reload
    assert_nil card.artist
    assert_nil card.stage
  end

  # Limitless writes every multiplier attack with U+00D7 (432 of them): an ASCII x would fingerprint
  # the hand-made printing apart from its scraped reprint.
  test "a trailing x after digits in the damage becomes the multiplication sign" do
    card = Card.new
    assert write(card, attributes: POKEMON,
                       attacks: [ EMBER.merge("name" => "A", "damage" => "110x"),
                                  EMBER.merge("name" => "B", "damage" => " 20X "),
                                  EMBER.merge("name" => "C", "damage" => "110\u00d7"),
                                  EMBER.merge("name" => "D", "damage" => "30+") ])

    assert_equal [ "110\u00d7", "20\u00d7", "110\u00d7", "30+" ], card.reload.attacks.pluck(:damage)
  end

  test "an Energy named like an ex gets no Pokémon subtype" do
    card = Card.new
    assert write(card, attributes: BASIC_FIRE.merge("name" => "Foo ex", "subtype" => "Special Energy", "rarity" => "Rare"))

    assert_nil card.reload.pokemon_subtype
  end

  test "an update replaces a held ability with another, then with none" do
    card = cards(:honedge)
    card.abilities.create!(name: "Keen Edge", effect: "Sharp.", position: 0)
    card = settled(card)
    cut = card.attacks.map { _1.attributes.slice(*%w[name cost damage effect]) }

    assert write(card, attacks: cut, abilities: [ { "name" => "Dull Edge", "effect" => "" } ])
    assert_equal [ "Dull Edge" ], card.reload.abilities.pluck(:name)

    assert write(card, attacks: cut, abilities: [])
    assert_equal [], card.reload.abilities.pluck(:name)
  end
end
