require "prawn"
require "vips"

# A deck's cards laid out on A4 for printing, each at exactly 6 cm x 8.5 cm — small enough to slide
# into a sleeve in front of a real card (63 x 88 mm). Nine to a page in a centred 3 x 3 grid of
# touching cards, so one cut serves two of them, with cut marks in the margins only.
#
# See docs/superpowers/specs/2026-10-07-proxy-sheet-design.md for the measurements below.
class Decks::ProxySheetExporter < ApplicationService
  class NothingToPrint < StandardError; end
  class TooManyPrintings < StandardError; end

  NOTHING_MISSING = "Every copy in this deck is backed by your collection: there are no proxies to print.".freeze
  EMPTY_DECK = "This deck has no cards to print.".freeze

  CM = 72 / 2.54
  PAGE_WIDTH, PAGE_HEIGHT = PDF::Core::PageGeometry::SIZES.fetch("A4")
  CARD_WIDTH = 6.0 * CM
  CARD_HEIGHT = 8.5 * CM
  COLUMNS = 3
  ROWS = 3
  PER_PAGE = COLUMNS * ROWS
  LEFT = (PAGE_WIDTH - COLUMNS * CARD_WIDTH) / 2
  BOTTOM = (PAGE_HEIGHT - ROWS * CARD_HEIGHT) / 2

  # Cut marks start this far outside the grid, so a slightly crooked cut never shows one.
  MARK_GAP = 0.2 * CM
  MARK_LENGTH = 0.8 * CM

  # A legal deck holds at most 60 distinct printings and the largest measured holds 37. The cap is
  # what bounds the number of outbound fetches one web request can make.
  MAX_PRINTINGS = 60

  # The images are fetched inside the web request, so they fail fast (Og::Renderer's numbers, for
  # the same reason) and in parallel: 37 serial fetches measured 2.3 s, 8 threads 0.5 s.
  FETCH_THREADS = 8
  ART_OPEN_TIMEOUT = 3
  ART_READ_TIMEOUT = 5
  # The timeouts bound one attempt, not one image: Net::HTTP retries an idempotent GET once after a
  # ReadTimeout, so a CDN that accepts and never answers costs 10 s an image (measured) — about 50 s
  # of a Puma thread for a 37-printing deck. The deadline bounds the whole sheet instead: past it the
  # request stops waiting, and whatever has not arrived prints as a placeholder. A healthy sheet's
  # fetches take 0.5 s.
  FETCH_DEADLINE = 8

  # Prawn decodes a PNG with transparency in pure Ruby to split its alpha (~63 ms an image, 2.35 s
  # for a 37-printing deck) and embeds a JPEG as it stands, so every art is re-encoded first.
  JPEG_QUALITY = 90

  FONT_NAME = Decks::TournamentPdfExporter::FONT_NAME
  FONT_FILES = Decks::TournamentPdfExporter::FONT_FILES

  def initialize(deck, missing_only: false)
    @deck = deck
    @missing_only = missing_only
  end

  def call
    slots = self.slots
    raise NothingToPrint, (@missing_only && @deck.deck_cards.any? ? NOTHING_MISSING : EMPTY_DECK) if slots.empty?

    cards = slots.map(&:card).uniq
    if cards.size > MAX_PRINTINGS
      raise TooManyPrintings,
            "A proxy sheet prints at most #{MAX_PRINTINGS} different printings; this deck holds #{cards.size}."
    end

    render(slots, fetch_arts(cards))
  end

  private

  # One entry per copy to print: Pokémon, Trainer, Energy, then name, then printing (set, then number
  # read as a number, so 9 comes before 10). Not quite the
  # deck page's order, which also splits Trainers by subtype; a sheet is cut up anyway.
  def slots
    @deck.deck_cards.includes(:card).to_a
         .sort_by { |dc| [ type_rank(dc.card), dc.card.name, dc.card.set_name.to_s, dc.card.set_number.to_i, dc.card.set_number.to_s ] }
         .flat_map { |dc| [ dc ] * copies(dc) }
  end

  def type_rank(card)
    Decks::Comparator::TYPE_ORDER.index(card.card_type) || Decks::Comparator::TYPE_ORDER.size
  end

  # A deck that is not physical backs no copy, so "the missing ones" are all of them — the rule
  # Decks::CardmarketExporter's missing style follows.
  def copies(deck_card)
    return deck_card.quantity unless @missing_only && @deck.physical?

    [ deck_card.proxies, 0 ].max
  end

  # card id => JPEG bytes, or no key when the art could not be had. URLs are read before the
  # threads start, so no thread touches Active Record. A thread still waiting at the deadline is left
  # to finish on its own — it holds a socket, not the request — and its answer is simply not read.
  def fetch_arts(cards)
    queue = Queue.new
    cards.each { |card| queue << [ card.id, card.image_url ] if card.image_url.present? }
    queue.close

    arts = {}
    lock = Mutex.new
    stop = false
    threads = Array.new([ FETCH_THREADS, queue.size ].min) do
      Thread.new do
        while !stop && (id, url = queue.pop)
          jpeg = fetch_art(url)
          lock.synchronize { arts[id] = jpeg } if jpeg
        end
      end
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FETCH_DEADLINE
    threads.each { |thread| thread.join([ deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0 ].max) }
    stop = true
    lock.synchronize { arts.dup }
  end

  # The loader is named from the URL's extension, never sniffed — Og::Renderer#load_art explains
  # why. Anything that is not an image, or not there, prints as a placeholder. The rescue is broad on
  # purpose, unlike Og::Renderer's: HttpFetcher lets some Net::HTTP errors through (a malformed
  # status line raises Net::HTTPBadResponse), and here one escaping image would fail the whole sheet
  # rather than cost one card.
  def fetch_art(url)
    bytes = HttpFetcher.call(url, open_timeout: ART_OPEN_TIMEOUT, read_timeout: ART_READ_TIMEOUT)
    image = case File.extname(URI.parse(url).path).downcase
    when ".png" then Vips::Image.pngload_buffer(bytes)
    when ".jpg", ".jpeg" then Vips::Image.jpegload_buffer(bytes)
    else return nil
    end
    image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha?
    image.jpegsave_buffer(Q: JPEG_QUALITY)
  rescue StandardError => e
    Rails.logger.warn "Proxy sheet: no art for #{url} (#{e.class}: #{e.message})"
    nil
  end

  def render(slots, arts)
    pdf = Prawn::Document.new(page_size: "A4", margin: 0, info: { Title: "#{@deck.name} — proxies" })
    pdf.font_families.update(FONT_NAME => FONT_FILES)
    pdf.font FONT_NAME

    slots.each_slice(PER_PAGE).with_index do |page, index|
      pdf.start_new_page if index.positive?
      page.each_with_index do |deck_card, position|
        x = LEFT + (position % COLUMNS) * CARD_WIDTH
        top = BOTTOM + (ROWS - position / COLUMNS) * CARD_HEIGHT
        art = arts[deck_card.card_id]
        if art
          pdf.image StringIO.new(art), at: [ x, top ], width: CARD_WIDTH, height: CARD_HEIGHT
        else
          draw_placeholder(pdf, deck_card.card, x, top)
        end
      end
      draw_cut_marks(pdf)
    end

    pdf.render
  end

  def draw_placeholder(pdf, card, x, top)
    pdf.stroke_color "999999"
    pdf.stroke_rectangle [ x, top ], CARD_WIDTH, CARD_HEIGHT
    pdf.fill_color "000000"
    pdf.text_box placeholder_lines(card).join("\n"),
                 at: [ x + 0.4 * CM, top - 0.4 * CM ], width: CARD_WIDTH - 0.8 * CM, height: CARD_HEIGHT - 0.8 * CM,
                 size: 11, align: :center, valign: :center, overflow: :shrink_to_fit
  end

  def placeholder_lines(card)
    [ card.name, [ card.set_name, card.set_number ].compact.join(" "), "Image unavailable" ]
  end

  # One mark at each end of every grid line, in the margin: the four vertical lines above and below
  # the grid, the four horizontal ones left and right of it.
  def draw_cut_marks(pdf)
    right = LEFT + COLUMNS * CARD_WIDTH
    top = BOTTOM + ROWS * CARD_HEIGHT

    pdf.stroke_color "000000"
    pdf.line_width 0.5
    (0..COLUMNS).each do |column|
      x = LEFT + column * CARD_WIDTH
      pdf.stroke_line [ x, top + MARK_GAP ], [ x, top + MARK_GAP + MARK_LENGTH ]
      pdf.stroke_line [ x, BOTTOM - MARK_GAP ], [ x, BOTTOM - MARK_GAP - MARK_LENGTH ]
    end
    (0..ROWS).each do |row|
      y = BOTTOM + row * CARD_HEIGHT
      pdf.stroke_line [ LEFT - MARK_GAP, y ], [ LEFT - MARK_GAP - MARK_LENGTH, y ]
      pdf.stroke_line [ right + MARK_GAP, y ], [ right + MARK_GAP + MARK_LENGTH, y ]
    end
  end
end
