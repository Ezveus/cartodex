require "test_helper"
require "tmpdir"

class Cards::OfficialImporterTest < ActiveSupport::TestCase
  FIXTURES = Rails.root.join("test/fixtures/files/official_cards")

  # Copies the named fragments into a scratch directory, so each test imports exactly the cards
  # it is about rather than all seventeen.
  def with_fragments(*names, slug: "30th")
    Dir.mktmpdir do |dir|
      names.each { FileUtils.cp(FIXTURES.join("#{_1}.html"), File.join(dir, "#{_1}.html")) }
      yield dir, slug
    end
  end

  def import(dir, slug: "30th", **options)
    Cards::OfficialImporter.call(dir: dir, slug: slug, set_code: "30C", **options)
  end

  test "creates the set and files every imported card under it" do
    with_fragments("30th_21", "30th_128") do |dir|
      result = import(dir, set_full_name: "30th Celebration")

      set = CardSet.find_by(code: "30C")
      assert_equal "30th Celebration", set.name
      assert_equal "international", set.region
      # `belongs_to :card_set` is optional and 44 catalogue printings legitimately carry a nil
      # card_set_id, so asserting set_name alone would pass on cards the set cannot reach.
      assert_equal 2, result.imported
      assert_equal 2, set.cards.count
      assert_equal set, Card.find_by(set_name: "30C", set_number: "21").card_set
    end
  end

  test "the set it creates is what CardSets::RescrapeJob walks to repair these rows" do
    # This is the documented end of the whole stopgap: once Limitless publishes 30C, the admin
    # panel's Rescrape rewrites every column this import could not fill. It reaches the cards
    # through card_set.cards, so a nil card_set_id would make it repair nothing, silently.
    requested = []
    original = Cards::Fetcher.method(:call)
    Cards::Fetcher.define_singleton_method(:call) { |url, **| requested << url; Card.new }

    with_fragments("30th_21", "30th_128") do |dir|
      import(dir)
      CardSets::RescrapeJob.perform_now(CardSet.find_by(code: "30C").id)
    end

    assert_includes requested, "https://limitlesstcg.com/cards/30C/21"
    assert_includes requested, "https://limitlesstcg.com/cards/30C/128"
  ensure
    Cards::Fetcher.define_singleton_method(:call, original)
  end

  test "writes the attacks before the card is saved, so they reach the fingerprint" do
    # compute_fingerprint is a before_save reading [name, hp, type_symbol, attacks, abilities].
    # Creating the card and then its attacks computes it over an empty list — and the fingerprint
    # is what Decks::ArchetypeDetector matches on and Cards::Printings groups by, so such a card
    # would silently never match an archetype and never offer a printing swap.
    with_fragments("30th_21") { |dir| import(dir) }
    greninja = Card.find_by(set_name: "30C", set_number: "21")

    attackless = Card.new(greninja.attributes.except("id", "fingerprint", "created_at", "updated_at"))
    attackless.send(:compute_fingerprint)

    assert_not_equal attackless.fingerprint, greninja.fingerprint
    assert_equal %w[Stealthy\ Slash Aqua\ Edge], greninja.attacks.map(&:name)
    assert_equal [ 0, 1 ], greninja.attacks.map(&:position)
  end

  test "gives an ex card its rule-box subtype, which nothing on Card derives" do
    # The only other writer is private to Cards::Fetcher. Decks::ArchetypeDetector reads
    # pokemon_subtype.rule_box to weight a member 3 instead of 2, so a nil here quietly
    # mis-ranks every archetype built on one of the set's 24 ex cards.
    with_fragments("30th_53") { |dir| import(dir) }

    assert_equal "Pokémon ex", Card.find_by(set_name: "30C", set_number: "53").pokemon_subtype.name
  end

  test "an ordinary Pokémon gets no subtype" do
    with_fragments("30th_130") { |dir| import(dir) }

    assert_nil Card.find_by(set_name: "30C", set_number: "130").pokemon_subtype
  end

  test "the imported card is findable by name, so it went through the callbacks" do
    # An insert_all anywhere on the create path leaves name_normalized nil, and the card is then
    # invisible to /cards, the spotlight and search_cards while every other assertion here passes.
    with_fragments("30th_21") { |dir| import(dir) }

    assert_includes Card.name_matching("greninja").pluck(:set_number), "21"
  end

  test "a Trainer saves with none of the Pokémon columns" do
    with_fragments("30th_128") { |dir| import(dir) }
    ultra_ball = Card.find_by(set_name: "30C", set_number: "128")

    assert_equal "Trainer", ultra_ball.card_type
    assert_equal "Item", ultra_ball.subtype
    assert_nil ultra_ball.hp
    assert_nil ultra_ball.type_symbol
    assert_nil ultra_ball.retreat_cost
  end

  test "leaves a printing already in the catalogue exactly as it was" do
    # The set will be re-imported from Limitless later and that row is the richer one. A count
    # assertion alone cannot tell "skipped" from "rewritten in place".
    Card.create!(
      name: "Placeholder", card_type: "Trainer", set_name: "30C", set_number: "128",
      rarity: "Common", regulation_mark: "J", price_eur: 1.5
    )

    with_fragments("30th_128") do |dir|
      result = import(dir)

      assert_equal 0, result.imported
      assert_equal 1, result.skipped
    end

    kept = Card.find_by(set_name: "30C", set_number: "128")
    assert_equal "Placeholder", kept.name
    assert_equal "J", kept.regulation_mark
    assert_equal 1.5, kept.price_eur
  end

  test "a card the model refuses is reported and does not take the run down with it" do
    # The realistic failure is not an unparseable file — that raises before any write — but a
    # perfectly parseable card Card refuses. Stripping the rarity does it, since Card validates
    # rarity present on everything but a Basic Energy.
    with_fragments("30th_21", "30th_53", "30th_128") do |dir|
      broken = File.join(dir, "30th_53.html")
      # The number stays; only the rarity goes. The point is a card that parses cleanly and that
      # the *model* then refuses — a ParseError would raise before any write and prove nothing
      # about whether the run is wrapped in a transaction.
      File.write(broken, File.read(broken).sub(%r{<span>53/128[^<]*</span>}, "<span>53/128</span>"))

      result = import(dir)

      assert_equal 2, result.imported
      assert_equal 1, result.failed.size
      assert_equal "30th_53.html", File.basename(result.failed.first.first)
      assert_match(/[Rr]arity/, result.failed.first.last)
    end

    # Nothing enclosing rolled the good rows back.
    assert Card.exists?(set_name: "30C", set_number: "21")
    assert Card.exists?(set_name: "30C", set_number: "128")
    assert_not Card.exists?(set_name: "30C", set_number: "53")
  end

  test "an error nobody rescues stops the run and keeps what was already written" do
    # The run is deliberately not wrapped in one transaction: a capture of 184 cards that dies
    # part-way should leave the cards it managed, and re-running skips them. Nothing else would
    # notice an enclosing transaction being added — the per-card rescue swallows the only failure
    # the other tests produce, so that transaction would never see anything to roll back.
    # Keyed on the card, not on a call count: the importer also parses one fragment up front to
    # learn the set's printed name, so a counter would silently target a different file.
    original = Cards::OfficialParser.method(:call)
    Cards::OfficialParser.define_singleton_method(:call) do |html|
      raise "the disk went away" if html.include?("Greninja")
      original.call(html)
    end

    with_fragments("30th_21", "30th_53", "30th_128", "30th_130") do |dir|
      assert_raises(RuntimeError) { import(dir) }
    end

    # Sorted order is 128, 130, 21, 53 — so the first two are committed and the fourth is
    # never reached.
    assert Card.exists?(set_name: "30C", set_number: "128")
    assert Card.exists?(set_name: "30C", set_number: "130")
    assert_not Card.exists?(set_name: "30C", set_number: "53")
  ensure
    Cards::OfficialParser.define_singleton_method(:call, original) if original
  end

  test "the set name given to the importer wins over the one printed on the card" do
    with_fragments("30th_21") do |dir|
      import(dir, set_full_name: "30th Anniversary Celebration")
    end

    assert_equal "30th Anniversary Celebration", CardSet.find_by(code: "30C").name
    # The card keeps what the source printed; only the set row takes the override.
    assert_equal "30th Celebration", Card.find_by(set_name: "30C", set_number: "21").set_full_name
  end

  test "with no name given, the set takes the one its own cards print" do
    # The argument and the fragments are two sources for one fact. Importing the Classic
    # Collection under the parent set's name would leave the /cards sidebar disagreeing with
    # every card listed under it.
    with_fragments("30th-c_1", slug: "30th-c") do |dir, slug|
      Cards::OfficialImporter.call(dir: dir, slug: slug, set_code: "30CC")
    end

    assert_equal "30th Classic Collection", CardSet.find_by(code: "30CC").name
  end

  test "never renames a set somebody already named" do
    # The `||=` is the CardSets::Importer rule: a re-run must not revert an admin's correction.
    CardSet.create!(code: "30C", name: "Thirtieth Anniversary")

    with_fragments("30th_21") { |dir| import(dir, set_full_name: "30th Celebration") }

    assert_equal "Thirtieth Anniversary", CardSet.find_by(code: "30C").name
  end

  test "a directory holding no fragment of this slug is a typo, not a finished import" do
    Dir.mktmpdir do |dir|
      FileUtils.cp(FIXTURES.join("30th_21.html"), File.join(dir, "30th_21.html"))

      # Reported success and exit 0 before, having created the set row — indistinguishable from
      # importing a set whose cards were all already held.
      assert_raises(ArgumentError) { import(dir, slug: "30TH") }
    end

    assert_not CardSet.exists?(code: "30C")
  end

  test "a fragment from the other set is refused rather than filed under this code" do
    Dir.mktmpdir do |dir|
      # Renamed on disk to look like this set; the page still says which set it is.
      FileUtils.cp(FIXTURES.join("30th-c_1.html"), File.join(dir, "30th_1.html"))

      result = import(dir)

      assert_equal 0, result.imported
      assert_match(/30th-c/, result.failed.first.last)
    end
  end

  test "reads only the slug it was asked for" do
    Dir.mktmpdir do |dir|
      FileUtils.cp(FIXTURES.join("30th_1.html"), File.join(dir, "30th_1.html"))
      FileUtils.cp(FIXTURES.join("30th-c_1.html"), File.join(dir, "30th-c_1.html"))

      result = import(dir, slug: "30th")

      # Both are number 1, and (set_name, set_number) is UNIQUE — reading both under one code
      # would be a collision, not a bigger import.
      assert_equal 1, result.imported
      assert_equal "Exeggcute", Card.find_by(set_name: "30C", set_number: "1").name
    end
  end

  test "forgets the cached filter values, which this import adds two rarities to" do
    with_real_cache do
      Card.filter_values
      assert_equal 0, count_queries { Card.filter_values }, "expected the lists to be cached"

      with_fragments("30th_129") { |dir| import(dir) }

      assert_operator count_queries { Card.filter_values }, :>, 0,
        "expected the import to have dropped the cached lists"
    end
  end

  # :null_store in test makes every fetch a miss, so without a real store the assertion above
  # passes whether or not anything was forgotten. Mirrors CardSets::ImporterTest.
  def with_real_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    yield
  ensure
    Rails.cache = original
  end
end
