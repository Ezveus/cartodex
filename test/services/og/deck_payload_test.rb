require "test_helper"

class Og::DeckPayloadTest < ActiveSupport::TestCase
  BUDEW_ART = "https://cards.test/budew.png".freeze
  OGERPON_ART = "https://cards.test/ogerpon.png".freeze
  FROAKIE_CRI_ART = "https://cards.test/froakie-cri.png".freeze
  FROAKIE_TWM_ART = "https://cards.test/froakie-twm.png".freeze
  HONEDGE_ART = "https://cards.test/honedge.png".freeze

  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  # Every fixture card carries image_url: nil (cards.yml sets none), so every test about artwork
  # has to write one. update_column and not update!: Card's before_save recomputes the
  # fingerprint the fixtures spell out by hand, and leaving updated_at alone is what lets the
  # digest tests below name a single cause.
  def give_art(card, url)
    card.update_column(:image_url, url)
  end

  def rule_box!(card)
    card.update_column(:pokemon_subtype_id, pokemon_subtypes(:pokemon_ex).id)
  end

  def add(card, quantity)
    @deck.deck_cards.create!(card: card, quantity: quantity)
  end

  def payload = Og::DeckPayload.call(@deck.reload)

  # --- What the banner says ---

  test "the deck payload is its name, its size and its format over the archetype's two cards" do
    @deck.update!(archetype: archetypes(:budew_ogerpon))
    give_art(cards(:budew_pre), BUDEW_ART)
    give_art(cards(:teal_mask_ogerpon_ex), OGERPON_ART)
    add(cards(:honedge), 4)
    add(cards(:doublade), 2)

    result = payload

    assert_equal "deck", result.kind
    assert_equal @deck.key, result.key
    assert_equal @deck.name, result.title
    assert_equal "6 cards · Standard (TWM-POR)", result.subtitle
    assert_equal [ BUDEW_ART, OGERPON_ART ], result.art_urls
    assert_match(/\A[0-9a-f]{16}\z/, result.digest)
  end

  # Copies, not rows — and in Ruby: `deck_cards.sum(:quantity)` in SQL would ignore the preload
  # every caller already has and spend a query on a number the loaded rows carry.
  test "the count is the sum of the copies, pluralized" do
    deck_card = add(cards(:honedge), 1)

    assert_equal "1 card · Standard (TWM-POR)", payload.subtitle

    deck_card.update!(quantity: 4)

    assert_equal "4 cards · Standard (TWM-POR)", payload.subtitle
  end

  # Standard is the one format whose name does not identify a card pool, so it is the only one
  # the subtitle qualifies. Deck#format_label already draws that line.
  test "a non-Standard deck's subtitle names no pool" do
    @deck.update!(format: "expanded")
    add(cards(:honedge), 1)

    subtitle = payload.subtitle

    assert_equal "1 card · Expanded", subtitle
    assert_not_includes subtitle, "TWM-POR"
  end

  test "a deck holding no cards still yields a valid payload" do
    result = payload

    assert_equal "0 cards · Standard (TWM-POR)", result.subtitle
    assert_equal [], result.art_urls
    assert_match(/\A[0-9a-f]{16}\z/, result.digest)
  end

  # --- The artwork ---

  test "the archetype's cards win over the deck's own Pokémon" do
    @deck.update!(archetype: archetypes(:budew_ogerpon))
    give_art(cards(:budew_pre), BUDEW_ART)
    give_art(cards(:teal_mask_ogerpon_ex), OGERPON_ART)
    give_art(cards(:honedge), HONEDGE_ART)
    add(cards(:honedge), 4)

    art_urls = payload.art_urls

    assert_equal [ BUDEW_ART, OGERPON_ART ], art_urls
    assert_not_includes art_urls, HONEDGE_ART
  end

  # An archetype is a human's answer to "which two cards is this deck", so it is not the first
  # rung of a fallback ladder: when its cards have no art the banner degrades to the static
  # Cartodex one rather than to a different pair of cards than the page shows.
  test "an archetype whose cards carry no artwork draws nothing else" do
    @deck.update!(archetype: archetypes(:budew_ogerpon))
    give_art(cards(:honedge), HONEDGE_ART)
    add(cards(:honedge), 4)

    assert_equal [], payload.art_urls
  end

  # Decks::ArchetypeDetector's suggestion order, copied at archetype_detector.rb:50-52. A
  # rule-box Pokémon wins outright, which is what this arrangement discriminates: Froakie has
  # 70 HP against Teal Mask Ogerpon ex's 210, and it is drawn first.
  test "the deck's own notable Pokémon are ranked rule-box first, then by HP" do
    rule_box!(cards(:froakie_cri))
    give_art(cards(:froakie_cri), FROAKIE_CRI_ART)
    give_art(cards(:teal_mask_ogerpon_ex), OGERPON_ART)
    give_art(cards(:budew_pre), BUDEW_ART)
    add(cards(:froakie_cri), 1)
    add(cards(:teal_mask_ogerpon_ex), 1)
    add(cards(:budew_pre), 4)

    art_urls = payload.art_urls

    assert_equal [ FROAKIE_CRI_ART, OGERPON_ART ], art_urls
    assert_not_includes art_urls, BUDEW_ART
  end

  # Copies are the third key, behind the rule box and HP: cards(:honedge) and cards(:froakie_cri)
  # both have 70 HP and neither has a rule box, so this pair is decided by nothing else.
  test "copies break a tie between two equally notable Pokémon" do
    give_art(cards(:froakie_cri), FROAKIE_CRI_ART)
    give_art(cards(:honedge), HONEDGE_ART)
    add(cards(:froakie_cri), 4)
    add(cards(:honedge), 1)

    assert_equal [ FROAKIE_CRI_ART, HONEDGE_ART ], payload.art_urls
  end

  # The `.uniq(&:name)` half of that sort, which the fixtures are built to catch: two printings
  # of Froakie with different HP rank first and second, so a payload that copies the sort and
  # drops the uniq draws one Pokémon twice — and `art_urls.size == 2` passes anyway. Hence the
  # assertion on the two Pokémon's *names*.
  test "the two arts come from Pokémon with different names" do
    give_art(cards(:froakie_cri), FROAKIE_CRI_ART)
    give_art(cards(:froakie_twm), FROAKIE_TWM_ART)
    give_art(cards(:budew_pre), BUDEW_ART)
    add(cards(:froakie_cri), 1)
    add(cards(:froakie_twm), 1)
    add(cards(:budew_pre), 1)

    art_urls = payload.art_urls
    names = art_urls.map { |url| Card.find_by!(image_url: url).name }

    assert_equal [ FROAKIE_CRI_ART, BUDEW_ART ], art_urls
    assert_not_includes art_urls, FROAKIE_TWM_ART
    assert_equal %w[Froakie Budew], names
  end

  # A card with no art does not consume one of the two slots: it is ranked, then dropped.
  test "a notable Pokémon with no artwork is skipped rather than drawn blank" do
    give_art(cards(:teal_mask_ogerpon_ex), OGERPON_ART)
    give_art(cards(:budew_pre), BUDEW_ART)
    add(cards(:teal_mask_ogerpon_ex), 1)
    add(cards(:froakie_cri), 1)
    add(cards(:budew_pre), 1)

    assert_equal [ OGERPON_ART, BUDEW_ART ], payload.art_urls
  end

  # Ranking Trainers by copies played would put Boss's Orders on every banner in the app, which
  # is the reason the detector's suggestion side is Pokémon-only.
  test "a Trainer is never drawn, however many copies the deck plays" do
    give_art(cards(:bosss_orders_meg), "https://cards.test/bosss-orders.png")
    give_art(cards(:budew_pre), BUDEW_ART)
    add(cards(:bosss_orders_meg), 4)
    add(cards(:budew_pre), 1)

    assert_equal [ BUDEW_ART ], payload.art_urls
  end

  # --- The digest ---
  #
  # DeckCard belongs_to :deck carries no `touch: true` (deck_card.rb:2), so every write
  # Api::DeckCardsController performs — add, remove, requantify, swap a printing — leaves
  # decks.updated_at untouched. Measured. The three tests below are what make the deck-cards'
  # count and newest timestamp load-bearing terms: without them the decklist would change the
  # banner's content and never its address, permanently, under Cache-Control: immutable.

  test "the digest moves when a deck card is created" do
    add(cards(:honedge), 1)
    before = payload.digest

    add(cards(:doublade), 1)

    assert_not_equal before, payload.digest
  end

  test "the digest moves when a deck card is requantified" do
    deck_card = add(cards(:honedge), 1)
    before = payload.digest

    # The row count does not change here and the quantity is not itself a digest term, so this
    # passes only if the newest deck-card updated_at is one. Second-resolution, hence travel.
    travel 2.seconds do
      deck_card.update!(quantity: 3)
    end

    assert_not_equal before, payload.digest
  end

  test "the digest moves when a deck card is destroyed" do
    deck_card = add(cards(:honedge), 1)
    before = payload.digest

    deck_card.destroy!

    assert_not_equal before, payload.digest
  end

  test "the digest moves when the deck itself is touched" do
    add(cards(:honedge), 1)
    before = payload.digest

    travel 1.hour do
      @deck.touch
    end

    assert_not_equal before, payload.digest
  end

  test "the digest moves when a drawn card's artwork changes" do
    give_art(cards(:budew_pre), BUDEW_ART)
    add(cards(:budew_pre), 1)
    before = payload.digest

    give_art(cards(:budew_pre), "https://cards.test/budew-alternate.png")

    assert_not_equal before, payload.digest
  end

  # Without this term, editing the banner's design leaves every generated file in place and the
  # change appears to do nothing.
  test "the digest moves when the layout version is bumped" do
    add(cards(:honedge), 1)
    before = payload.digest

    with_layout_version(Og::LAYOUT_VERSION + 1) do
      assert_not_equal before, payload.digest
    end
  end

  # --- The cost ---

  # The preload set this builder needs, spelled out because it is the whole budget: both
  # branches of DecksController#show are measured by a literal flat-cost test. The Standard
  # pool and *both of its bounds* are part of it — Deck#format_label names the pool, and
  # StandardPool#name reads the two card sets.
  test "costs no query when the deck's associations are preloaded" do
    @deck.update!(archetype: archetypes(:budew_ogerpon))
    add(cards(:teal_mask_ogerpon_ex), 1)
    deck = Deck.with_standard_pool
      .includes(archetype: [ :primary_card, :secondary_card ], deck_cards: { card: :pokemon_subtype })
      .find(@deck.id)

    assert_queries_count(0) do
      Og::DeckPayload.call(deck)
    end
  end

  private

  # A real constant, restored in an ensure — the idiom
  # test/controllers/admin/standings_imports_controller_test.rb:392 uses for the same reason:
  # every later test in this process would otherwise inherit the bumped value.
  #
  # Reading Og::LAYOUT_VERSION requires app/services/og/payload.rb to have been loaded, which
  # is why callers compute a digest before calling this: Zeitwerk autoloads Og::Payload, and
  # the constant lives in app/services/og.rb, the explicit namespace file that exists for this.
  def with_layout_version(version)
    original = Og::LAYOUT_VERSION
    Og.send(:remove_const, :LAYOUT_VERSION)
    Og.const_set(:LAYOUT_VERSION, version)
    yield
  ensure
    Og.send(:remove_const, :LAYOUT_VERSION)
    Og.const_set(:LAYOUT_VERSION, original)
  end
end
