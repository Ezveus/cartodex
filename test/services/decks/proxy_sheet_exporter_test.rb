require "test_helper"
require "vips"

class Decks::ProxySheetExporterTest < ActiveSupport::TestCase
  # A4 in points, and the two dimensions the feature exists for. Spelled out rather than read off
  # the class, so that a wrong constant cannot make the test agree with it.
  A4_WIDTH = 595.28
  A4_HEIGHT = 841.89
  CARD_WIDTH = 6.0 / 2.54 * 72   # 170.08
  CARD_HEIGHT = 8.5 / 2.54 * 72  # 240.94
  GRID_LEFT = (A4_WIDTH - 3 * CARD_WIDTH) / 2
  GRID_BOTTOM = (A4_HEIGHT - 3 * CARD_HEIGHT) / 2
  GRID_TOP = GRID_BOTTOM + 3 * CARD_HEIGHT
  GRID_RIGHT = GRID_LEFT + 3 * CARD_WIDTH

  # The ten fixture cards a concurrency test needs, each with an art of its own.
  TEN_CARDS = %i[honedge doublade trainer_card budew_pre budew_asc froakie_cri froakie_twm
                 bosss_orders_meg basic_psychic_energy teal_mask_ogerpon_ex].freeze

  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @fetched = []
    @arts = {}
    stub_fetch { |url| @arts.fetch(url) { raise HttpFetcher::FetchError, "no art for #{url}" } }
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  # --- geometry ------------------------------------------------------------

  test "draws every card at exactly 6 cm by 8.5 cm on an A4 page" do
    with_art(cards(:honedge), quantity: 4)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_equal [ [ A4_WIDTH, A4_HEIGHT ] ], media_boxes(pdf).uniq
    placements = image_placements(pdf)
    assert_equal 4, placements.size
    placements.each do |p|
      assert_in_delta CARD_WIDTH, p[:width], 0.01
      assert_in_delta CARD_HEIGHT, p[:height], 0.01
    end
  end

  test "lays nine cards per page in a centred 3 by 3 grid of touching cards" do
    with_art(cards(:honedge), quantity: 9)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_equal 1, media_boxes(pdf).size
    placements = image_placements(pdf)
    xs = placements.map { _1[:x] }.uniq.sort
    ys = placements.map { _1[:y] }.uniq.sort
    assert_equal 3, xs.size
    assert_equal 3, ys.size
    # Touching: each column starts where the previous one ends.
    xs.each_cons(2) { |a, b| assert_in_delta CARD_WIDTH, b - a, 0.01 }
    ys.each_cons(2) { |a, b| assert_in_delta CARD_HEIGHT, b - a, 0.01 }
    # Centred: equal margins on both sides, on both axes.
    assert_in_delta A4_WIDTH - (xs.last + CARD_WIDTH), xs.first, 0.01
    assert_in_delta A4_HEIGHT - (ys.last + CARD_HEIGHT), ys.first, 0.01
  end

  test "sixty copies make seven pages" do
    with_art(cards(:honedge), quantity: 60)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_equal 7, media_boxes(pdf).size
    assert_equal 60, image_placements(pdf).size
  end

  test "a single card sits in the top-left slot" do
    with_art(cards(:honedge), quantity: 1)

    placement = image_placements(Decks::ProxySheetExporter.call(@deck)).sole

    assert_in_delta GRID_LEFT, placement[:x], 0.01
    assert_in_delta GRID_TOP - CARD_HEIGHT, placement[:y], 0.01
  end

  # --- order, read off the paper ---------------------------------------------

  test "the paper reads Pokémon, Trainer, Energy, then name, then printing, left to right and top to bottom" do
    # Created in the reverse order, so that insertion order cannot pass for the rule. The two Budew
    # share a name, so the printing is what orders them: ASC 16 before PRE 4.
    energy = with_art(cards(:basic_psychic_energy), quantity: 1, color: [ 0, 0, 220 ])
    trainer = with_art(cards(:trainer_card), quantity: 1, color: [ 0, 220, 0 ])
    budew_pre = with_art(cards(:budew_pre), quantity: 1, color: [ 220, 0, 220 ])
    honedge = with_art(cards(:honedge), quantity: 2, color: [ 220, 0, 0 ])
    budew_asc = with_art(cards(:budew_asc), quantity: 1, color: [ 0, 220, 220 ])
    doublade = with_art(cards(:doublade), quantity: 2, color: [ 220, 220, 0 ])

    pdf = Decks::ProxySheetExporter.call(@deck)

    expected = [ budew_asc, budew_pre, doublade, doublade, honedge, honedge, trainer, energy ]
    assert_equal expected.map { color_of(_1) }, colors_in_reading_order(pdf)
  end

  test "two printings of one name in one set are ordered by number, as numbers" do
    budew_asc = cards(:budew_asc)
    budew_nine = cards(:budew_pre)
    budew_nine.update_columns(set_name: budew_asc.set_name, set_number: "9")
    with_art(budew_asc, quantity: 1, color: [ 0, 220, 220 ])
    with_art(budew_nine, quantity: 1, color: [ 220, 0, 220 ])

    assert_equal [ color_of(budew_nine), color_of(budew_asc) ], colors_in_reading_order(Decks::ProxySheetExporter.call(@deck))
  end

  # --- copies --------------------------------------------------------------

  test "the whole-deck style prints every copy, whatever the collection backs" do
    @deck.update!(physical: true)
    with_art(cards(:honedge), quantity: 4, owned_copies: 3)

    assert_equal 4, image_placements(Decks::ProxySheetExporter.call(@deck)).size
  end

  test "the missing style prints only the proxies of a physical deck, and fetches nothing else" do
    @deck.update!(physical: true)
    with_art(cards(:honedge), quantity: 4, owned_copies: 4)
    doublade = with_art(cards(:doublade), quantity: 3, owned_copies: 1)

    pdf = Decks::ProxySheetExporter.call(@deck, missing_only: true)

    assert_equal 2, image_placements(pdf).size
    assert_equal [ doublade.image_url ], @fetched.map(&:first)
  end

  test "the missing style prints the whole count of a deck that is not physical" do
    @deck.update!(physical: false)
    with_art(cards(:honedge), quantity: 4)
    # Unreachable through the model, which zeroes owned_copies off a physical deck: this is what
    # makes the `physical?` half of the rule observable at all.
    @deck.deck_cards.sole.update_column(:owned_copies, 3)

    pdf = Decks::ProxySheetExporter.call(@deck, missing_only: true)

    assert_equal 4, image_placements(pdf).size
  end

  test "the missing style refuses a deck whose every copy is backed" do
    @deck.update!(physical: true)
    with_art(cards(:honedge), quantity: 2, owned_copies: 2)

    error = assert_raises(Decks::ProxySheetExporter::NothingToPrint) do
      Decks::ProxySheetExporter.call(@deck, missing_only: true)
    end
    assert_equal Decks::ProxySheetExporter::NOTHING_MISSING, error.message
  end

  test "an empty deck has nothing to print" do
    error = assert_raises(Decks::ProxySheetExporter::NothingToPrint) { Decks::ProxySheetExporter.call(@deck) }
    assert_equal Decks::ProxySheetExporter::EMPTY_DECK, error.message
  end

  # A legal deck holds at most 60 cards, so 60 printings; the test below works at 2 for speed.
  test "the cap is sixty printings" do
    assert_equal 60, Decks::ProxySheetExporter::MAX_PRINTINGS
  end

  test "MAX_PRINTINGS counts distinct printings, not copies, and refuses only past it" do
    with_constant(Decks::ProxySheetExporter, :MAX_PRINTINGS, 2) do
      with_art(cards(:honedge), quantity: 3)
      with_art(cards(:doublade), quantity: 3)

      # Exactly the cap, six copies: printed.
      assert_equal 6, image_placements(Decks::ProxySheetExporter.call(@deck)).size

      with_art(cards(:trainer_card), quantity: 1)
      @fetched.clear

      assert_raises(Decks::ProxySheetExporter::TooManyPrintings) { Decks::ProxySheetExporter.call(@deck) }
      assert_empty @fetched
    end
  end

  # --- fetching ------------------------------------------------------------

  test "fetches each distinct printing once, with Og::Renderer's short timeouts" do
    with_art(cards(:honedge), quantity: 4)
    with_art(cards(:doublade), quantity: 3)

    Decks::ProxySheetExporter.call(@deck)

    assert_equal [ cards(:doublade).image_url, cards(:honedge).image_url ].sort, @fetched.map(&:first).sort
    @fetched.each { |_url, options| assert_equal({ open_timeout: 3, read_timeout: 5 }, options) }
  end

  test "fetches in parallel, at most eight at a time" do
    TEN_CARDS.each { with_art(cards(_1), quantity: 1) }
    in_flight = 0
    peak = 0
    lock = Mutex.new
    bytes = png_bytes
    stub_fetch do |_url|
      lock.synchronize { in_flight += 1; peak = [ peak, in_flight ].max }
      sleep 0.05
      lock.synchronize { in_flight -= 1 }
      bytes
    end

    Decks::ProxySheetExporter.call(@deck)

    assert_operator peak, :>=, 2, "the fetches ran one at a time"
    assert_operator peak, :<=, 8
  end

  # In production each thread would check out a connection of its own from a pool of five; in a
  # test, transactional fixtures share one, so only watching where the queries run can see it.
  test "no fetch thread touches Active Record" do
    TEN_CARDS.each { with_art(cards(_1), quantity: 1) }
    threads = []
    callback = ->(*) { threads << Thread.current }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      Decks::ProxySheetExporter.call(Deck.find(@deck.id))
    end

    assert_not_empty threads
    assert_equal [ Thread.current ], threads.uniq
  end

  # A hung CDN costs 10 s an image through Net::HTTP's own retry; the sheet must not wait for it.
  test "a fetch still running at the deadline prints a placeholder instead of holding the request" do
    with_art(cards(:honedge), quantity: 1)
    slow = with_art(cards(:doublade), quantity: 1)
    fast = @arts[cards(:honedge).image_url]
    stub_fetch do |url|
      sleep 3 if url == slow.image_url
      fast
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pdf = with_constant(Decks::ProxySheetExporter, :FETCH_DEADLINE, 0.3) { Decks::ProxySheetExporter.call(@deck) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 1.5, "the sheet waited for the hung fetch"
    assert_equal 1, image_placements(pdf).size
    assert_equal 1, placeholder_frames(pdf).size
  end

  # HttpFetcher maps timeouts and refused connections to FetchError but lets a malformed response
  # through; inside a fetch thread that would re-raise from Thread#value and fail every card.
  test "an error HttpFetcher does not map still costs one card, not the sheet" do
    with_art(cards(:honedge), quantity: 1)
    broken = with_art(cards(:doublade), quantity: 1)
    fine = @arts[cards(:honedge).image_url]
    stub_fetch { |url| url == broken.image_url ? raise(Net::HTTPBadResponse, "wrong status line") : fine }

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_equal 1, image_placements(pdf).size
    assert_equal 1, placeholder_frames(pdf).size
  end

  # --- conversion ----------------------------------------------------------

  # The real art is a palette PNG with a tRNS chunk, transparent at the rounded corners. Prawn
  # splits a PNG's alpha in pure Ruby (~63 ms an image, measured) and embeds a JPEG as it stands.
  test "a palette PNG with transparency is embedded as a JPEG, its transparent pixels white" do
    bytes = png_bytes(color: [ 30, 30, 30 ], transparent_corner: true, palette: true)
    assert_equal 3, bytes.byteslice(25).ord, "precondition: a palette PNG, the shape Limitless serves"
    with_art(cards(:honedge), quantity: 1, bytes:)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_match %r{/Filter \[/DCTDecode\]}, pdf
    assert_not_includes pdf, "/SMask", "a transparent PNG reached Prawn as a PNG"
    art = embedded_images(pdf).values.sole
    # Black is libvips' default flatten background, and would read ~30 here. JPEG rings at the
    # corner's edge, hence a pixel inside it and a threshold short of 255.
    assert art.getpoint(3, 3).all? { _1 >= 220 }, "the transparent corner is not white: #{art.getpoint(3, 3)}"
    assert art.getpoint(30, 40).all? { _1 <= 60 }, "the opaque body changed colour"
  end

  test "a JPEG art is drawn too" do
    card = cards(:honedge)
    @deck.deck_cards.create!(card: card, quantity: 1)
    card.update_column(:image_url, "https://cdn.test/honedge.jpg")
    @arts[card.image_url] = (Vips::Image.black(46, 64) + [ 120, 60, 30 ]).cast(:uchar).jpegsave_buffer

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_equal 1, image_placements(pdf).size
    assert_empty placeholder_frames(pdf)
  end

  test "bytes that are not an image print a placeholder rather than failing the sheet" do
    with_art(cards(:honedge), quantity: 1, bytes: "<html>not an image</html>")

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_empty image_placements(pdf)
    assert_equal 1, placeholder_frames(pdf).size
  end

  # Once any banner has been drawn, the process has the SVG loader unblocked; a sniffing loader
  # would then render whatever SVG the CDN answers a `.png` URL with (Og::Renderer#load_art).
  test "an SVG served under a .png URL is refused, not sniffed and rendered" do
    Og::Renderer.allow_generated_svg!
    svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><rect width="40" height="40" fill="red"/></svg>)
    with_art(cards(:honedge), quantity: 1, bytes: svg)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_empty image_placements(pdf)
    assert_equal 1, placeholder_frames(pdf).size
  end

  # --- placeholders --------------------------------------------------------

  test "a card whose image cannot be fetched prints a placeholder naming it, and the others still print" do
    with_art(cards(:honedge), quantity: 1)
    broken = cards(:doublade)
    broken.update_column(:image_url, "https://cdn.test/broken.png")
    @deck.deck_cards.create!(card: broken, quantity: 2)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_equal 1, image_placements(pdf).size
    assert_equal 2, placeholder_frames(pdf).size
    assert_equal [ "Doublade", "#{broken.set_name} #{broken.set_number}", "Image unavailable" ],
                 Decks::ProxySheetExporter.new(@deck).send(:placeholder_lines, broken)
  end

  # Prawn's built-in Helvetica raises on these glyphs, so a placeholder in the default font would
  # turn a missing image into a 500 for exactly the cards that carry them.
  test "a placeholder writes its text in a font that encodes every card name" do
    card = cards(:honedge)
    card.update_columns(name: "Nidoran♀ ♢", image_url: nil)
    @deck.deck_cards.create!(card: card, quantity: 1)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_match %r{/BaseFont /\w+\+DejaVuSans}, pdf
    assert_match(/\bT[jJ]\b/, pdf)
    assert_equal 1, placeholder_frames(pdf).size
  end

  test "a card with no image_url prints a placeholder without a fetch" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)

    pdf = Decks::ProxySheetExporter.call(@deck)

    assert_equal 1, placeholder_frames(pdf).size
    assert_empty @fetched
  end

  # --- cut marks -----------------------------------------------------------

  test "cut marks extend every grid line into the margins, and none crosses a card" do
    with_art(cards(:honedge), quantity: 1)

    segments = line_segments(Decks::ProxySheetExporter.call(@deck))

    # Four vertical grid lines, marked above and below; four horizontal ones, left and right.
    assert_equal 16, segments.size
    grid_xs = 4.times.map { GRID_LEFT + _1 * CARD_WIDTH }
    grid_ys = 4.times.map { GRID_BOTTOM + _1 * CARD_HEIGHT }
    segments.each do |(x1, y1), (x2, y2)|
      label = [ x1, y1, x2, y2 ].inspect
      if (x1 - x2).abs < 0.01
        assert grid_xs.any? { (_1 - x1).abs < 0.01 }, "a vertical mark off every grid line: #{label}"
        assert [ y1, y2 ].max <= GRID_BOTTOM + 0.01 || [ y1, y2 ].min >= GRID_TOP - 0.01, "a mark crosses the cards: #{label}"
      else
        assert grid_ys.any? { (_1 - y1).abs < 0.01 }, "a horizontal mark off every grid line: #{label}"
        assert [ x1, x2 ].max <= GRID_LEFT + 0.01 || [ x1, x2 ].min >= GRID_RIGHT - 0.01, "a mark crosses the cards: #{label}"
      end
      # A mark that touches the grid shows on a card cut a hair inside its line.
      nearest = (x1 - x2).abs < 0.01 ? [ y1, y2 ].map { |y| [ (y - GRID_BOTTOM).abs, (y - GRID_TOP).abs ].min }.min
                                      : [ x1, x2 ].map { |x| [ (x - GRID_LEFT).abs, (x - GRID_RIGHT).abs ].min }.min
      assert_operator nearest, :>=, 1 / 2.54 * 72 / 10, "a mark starts less than 1 mm from the grid: #{label}"
    end
  end

  test "every page carries its cut marks" do
    with_art(cards(:honedge), quantity: 10)

    assert_equal 32, line_segments(Decks::ProxySheetExporter.call(@deck)).size
  end

  private

  # Gives the card a URL of its own, adds it to the deck and registers the bytes its fetch answers.
  def with_art(card, quantity:, owned_copies: 0, color: [ 120, 60, 30 ], bytes: nil)
    card.update_column(:image_url, "https://cdn.test/#{card.set_name}_#{card.set_number}.png")
    @deck.deck_cards.create!(card: card, quantity: quantity, owned_copies: owned_copies)
    @arts[card.image_url] = bytes || png_bytes(color:)
    @colors ||= {}
    @colors[card.id] = color
    card
  end

  def color_of(card) = @colors.fetch(card.id)

  def stub_fetch(&answer)
    fetched = @fetched
    HttpFetcher.define_singleton_method(:call) do |url, **options|
      fetched << [ url, options ]
      answer.call(url)
    end
  end

  def png_bytes(color: [ 120, 60, 30 ], transparent_corner: false, palette: false)
    image = (Vips::Image.black(46, 64) + color).cast(:uchar)
    if transparent_corner
      alpha = (Vips::Image.black(46, 64) + 255).cast(:uchar).draw_rect(0, 0, 0, 12, 12, fill: true)
      image = image.bandjoin(alpha)
    end
    image.pngsave_buffer(palette:)
  end

  # Prawn writes uncompressed content streams by default, so placements can be read off the bytes
  # themselves — the output, rather than the calls that were meant to produce it.
  def media_boxes(pdf)
    pdf.scan(%r{/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]}).map { |w, h| [ w.to_f.round(2), h.to_f.round(2) ] }
  end

  def image_placements(pdf)
    pdf.scan(%r{([\d.]+) 0\.0 0\.0 ([\d.]+) ([\d.]+) ([\d.]+) cm\s*/(I\d+) Do}).map do |w, h, x, y, name|
      { width: w.to_f, height: h.to_f, x: x.to_f, y: y.to_f, name: }
    end
  end

  # XObject name => decoded image. Prawn numbers images across the whole document, so a name means
  # one image on every page.
  def embedded_images(pdf)
    objects = pdf.scan(/(\d+) 0 obj\n<<([^<>]*)>>\nstream\n(.*?)\nendstream/m)
                 .select { |_num, dict, _data| dict.include?("/Subtype /Image") }
                 .to_h { |num, _dict, data| [ num, data ] }
    pdf.scan(%r{/(I\d+) (\d+) 0 R}).uniq.to_h do |name, num|
      [ name, Vips::Image.jpegload_buffer(objects.fetch(num)) ]
    end
  end

  # A one-page sheet's placements top to bottom and left to right, each named by its art's colour.
  def colors_in_reading_order(pdf)
    assert_equal 1, media_boxes(pdf).size, "reading order is only defined here for one page"
    images = embedded_images(pdf)
    palette = @colors.values
    image_placements(pdf).sort_by { |p| [ -p[:y], p[:x] ] }.map do |p|
      image = images.fetch(p[:name])
      average = (0..2).map { image.extract_band(_1).avg }
      palette.min_by { |c| c.zip(average).sum { |a, b| (a - b)**2 } }
    end
  end

  def line_segments(pdf)
    pdf.scan(/([\d.]+) ([\d.]+) m\s*([\d.]+) ([\d.]+) l/).map do |x1, y1, x2, y2|
      [ [ x1.to_f, y1.to_f ], [ x2.to_f, y2.to_f ] ]
    end
  end

  # A placeholder is a card-sized stroked frame; the sheet draws no other rectangle.
  def placeholder_frames(pdf)
    pdf.scan(/([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) re\s*S/).select do |_x, _y, w, h|
      (w.to_f - CARD_WIDTH).abs < 0.01 && (h.to_f - CARD_HEIGHT).abs < 0.01
    end
  end
end
