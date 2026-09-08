# libvips is required here rather than lazily inside #call, because
# config/environments/test.rb eager-loads under CI: a missing native library must
# be a boot failure in CI (loud, once) rather than a 500 on the first crawler
# request in production.
require "cgi"
require "vips"

# Draws one 1200x630 Open Graph banner from an Og::Payload and hands back JPEG
# bytes. This is the only file in the app that knows about libvips; all the
# product knowledge (what the title says, which cards are chosen) lives in the
# Og::*Payload builders.
#
# Layout, at 1200x630 ("layout B" of the spike, the approved one):
#
#   * the first art's illustration window, upscaled, gaussian-blurred and
#     darkened, filling the frame;
#   * a vertical --ink-900 scrim over it, SCRIM_TOP to SCRIM_BOTTOM, which is
#     what keeps the title legible on any artwork — measured, not assumed;
#   * a 10px --flare rule across the very top;
#   * the whole cards, slightly turned, on the right;
#   * the title, the subtitle and the white Cartodex mark on the left.
#
# Zero resolvable arts falls back to the plain branded banner: no photograph, no
# scrim, no cards. One art is the two-art layout with one card.
module Og
  class Renderer < ApplicationService
    WIDTH = 1200
    HEIGHT = 630

    # Design tokens, as RGB triples (the text compositor needs numbers) and as
    # hex (the SVG needs strings). Kept in one place so the two cannot drift.
    INK_900 = "#0E1320".freeze
    PAPER   = "#F7F8FA".freeze
    FLARE   = "#DD2C16".freeze

    INK_900_RGB = [ 14, 19, 32 ].freeze
    INK_300_RGB = [ 147, 160, 180 ].freeze
    PAPER_RGB   = [ 247, 248, 250 ].freeze

    # The region the title and subtitle occupy, and therefore the region whose
    # contrast against --paper is measured. Its right edge (70 + 580 = 650) stops
    # short of the leftmost card (x = 660) on purpose: the cards are composited
    # after the measurement, so anything under them would be measured as
    # background and is not.
    TEXT_COLUMN = { x: 70, y: 336, width: 580, height: 268 }.freeze

    # The scrim's two stops, fixed. This is the pair the spike's approved layout-b.jpg used, and
    # restoring it is what deleted the adaptive ladder that stood here.
    #
    # The ladder walked five top-stop opacities until the text column cleared CONTRAST_TARGET. It
    # could never move. Measured on this geometry: TEXT_COLUMN sits at y 336..604, where this
    # gradient is already ~0.83 opaque, so even a flat **white** art reads 10.67:1 there — against
    # a 4.5 target. A flat light grey reads 12.23:1 and a flat black 17.96:1. No artwork that
    # exists can drive the walk off rung one, which makes the walk a mechanism in appearance only.
    #
    # The alternative was to weaken the gradient until the ladder mattered (a 0.45 -> 0.49 wash
    # makes white read 3.14:1, so it does fire) — but that is a visibly lighter banner than the one
    # that was approved, for the sake of keeping a branch alive. The guarantee the ladder was meant
    # to provide is now an assertion instead: Og::RendererTest measures the worst case and requires
    # it to clear CONTRAST_TARGET, so moving TEXT_COLUMN up or flattening these stops turns red.
    SCRIM_TOP = 0.45
    SCRIM_BOTTOM = 0.96

    # WCAG AA for large text is 3:1; this is the 4.5:1 body-text threshold,
    # because a banner is read at thumbnail size in a chat list.
    CONTRAST_TARGET = 4.5

    # 92.8 KB against a PNG's 443 KB for the same image, measured on the spike.
    QUALITY = 85

    # Much shorter than HttpFetcher's own 10/30, because two serial fetches sit inside one web
    # request here: at the defaults a host that accepts and never answers held a Puma thread for
    # 120.4 s (measured), and there are five threads. A banner is the most disposable thing this
    # app serves — a missed art costs one card in one preview — so failing fast is strictly better
    # than waiting, and the 60/min budget cannot bound thread-seconds on its own.
    ART_OPEN_TIMEOUT = 3
    ART_READ_TIMEOUT = 5

    FONT = Rails.root.join("vendor/fonts/Archivo.ttf")

    # Asking for "Archivo" by family name does not fail without this file: it
    # renders DejaVu, correctly and silently, at slightly different metrics
    # (measured: 492x342 for the same string under both "Archivo ExtraBold 76"
    # and "DejaVu Sans Bold 76", versus 437x320 with the fontfile). Nothing about
    # the output says the brand font was not used, which is why every text layer
    # in this class goes through the one #text_layer below.
    FONT_FAMILY = "Archivo".freeze

    # Vips::Image.text sizes in points, so pinning the DPI is what makes the
    # point sizes below mean pixels.
    DPI = 72

    TITLE_SIZES = [ 60, 50, 42, 36 ].freeze
    TITLE_MAX_HEIGHT = 200
    SUBTITLE_SIZE = 30
    SUBTITLE_GAP = 26

    # Fractions of a modern card's face taken up by its illustration window.
    # Measured on the 460x640 PNGs Limitless serves, which is also
    # deck_image_export_controller.js's CARD_WIDTH/CARD_HEIGHT.
    ART_WINDOW = { x: 0.075, y: 0.135, width: 0.850, height: 0.335 }.freeze

    # Four fifths of a render is this blur, and it is not decoration: the
    # illustration window is about 410x230 real pixels and filling 1200x630 with
    # it is a 2.9x upscale, which is soft whether or not we ask for it.
    BLUR_SIGMA = 14

    # Geometry of the right-hand cards: width, rotation, and where each lands.
    CARD_WIDTH = 300
    CARDS = [
      { angle: -8, x: 660, y: 190 },
      { angle:  6, x: 840, y: 150 }
    ].freeze

    # The playmat mark, in --paper, as SVG because it is geometry. Kept in the
    # scrim/frame SVG rather than composited, for the reason the rule is: the SVG
    # carries everything that is not text.
    MARK = <<~SVG.freeze
      <g transform="translate(%<x>d,%<y>d) scale(%<scale>f)">
        <g transform="rotate(-11 256 256)">
          <rect x="48" y="112" width="416" height="304" rx="32" fill="#{PAPER}"/>
          <rect x="68"  y="304" width="64" height="90" rx="10" fill="#{INK_900}" opacity=".45"/>
          <rect x="146" y="304" width="64" height="90" rx="10" fill="#{INK_900}" opacity=".45"/>
          <rect x="224" y="304" width="64" height="90" rx="10" fill="#{INK_900}" opacity=".45"/>
          <rect x="302" y="304" width="64" height="90" rx="10" fill="#{INK_900}" opacity=".45"/>
          <rect x="380" y="304" width="64" height="90" rx="10" fill="#{INK_900}" opacity=".45"/>
        </g>
        <rect x="204" y="96" width="104" height="146" rx="16" fill="#{FLARE}"/>
      </g>
    SVG

    MARK_X = 70
    MARK_Y = 60
    MARK_SIZE = 88

    RULE_HEIGHT = 10

    def initialize(payload)
      @payload = payload
    end

    # Adding the ruby-vips gem made ActiveStorage call Vips.block_untrusted(true) at boot
    # (activestorage-8.1.3.1/lib/active_storage/vips.rb:43), which blocks every libvips loader
    # upstream has not fuzzed — svgload among them. Every banner therefore raised
    # `Vips::Error: svgload_buffer: operation is blocked`, and the spike could not have caught it:
    # it ran without Rails. This re-enables exactly that one loader, and nothing else.
    #
    # Safe here, and #load_art is what makes it so rather than a promise in a comment. The block
    # protects untrusted *input*; the only SVG this process loads is the frame #svg builds from a
    # heredoc in this file, and every byte that arrives off the network goes to a loader named from
    # its URL's extension instead of one libvips picked by sniffing. Written the sniffing way — and
    # it was — an unblocked svgload meant the CDN chose the loader for its own response, which a
    # review reproduced as a 16000x16000 SVG holding a Puma thread for 66.8 s at 1160 MB.
    #
    # ActiveStorage, whose protection this narrows, is not used at all: no has_one_attached or
    # has_many_attached anywhere in app/, and no active_storage tables in db/schema.rb. Should this
    # app ever accept a file upload, this line has to be revisited.
    #
    # Called from #svg and not at require-time, because ActiveStorage installs its block during
    # boot and eager loading may pull this class in before that: a load-time unblock would be
    # silently undone. #svg rather than #call because a test that exercises a private layer
    # directly — measuring the scrim, say — never goes through #call, and two of them went red
    # exactly that way. `Vips.block` blocks or unblocks a class "and below", so naming
    # VipsForeignLoadSvg covers both the file and the buffer operation.
    def self.allow_generated_svg!
      return if @svg_allowed

      ::Vips.block("VipsForeignLoadSvg", false)
      @svg_allowed = true
    end

    # `complete` is false when any art the payload asked for did not resolve, and it exists so
    # that Og::Cache can serve a degraded banner without storing it. The digest cannot express
    # this — it is computed from the record and the art URLs, never from whether the fetch worked
    # — so without the flag one transient CDN failure pins an artless banner at that address until
    # the subject is next edited, under a `Cache-Control: immutable` that tells every client never
    # to look again.
    Result = Struct.new(:bytes, :complete, keyword_init: true)

    # => Result, whose bytes are a JPEG of exactly WIDTH x HEIGHT.
    def call
      wanted = Array(@payload.art_urls).first(CARDS.size).size
      arts = fetch_arts
      frame = arts.empty? ? plain_frame : photo_frame(arts.first)

      layers = whole_cards(arts) + text_layers
      frame = frame.composite(layers.map { |l| l[:image] }, [ :over ] * layers.size,
                              x: layers.map { |l| l[:x] }, y: layers.map { |l| l[:y] })
      Result.new(bytes: flatten(frame).write_to_buffer(".jpg[Q=#{QUALITY}]"),
                 complete: arts.size == wanted)
    end

    private

    # --- artwork -------------------------------------------------------------

    # A failed art degrades: two arts to one, or one to the branded banner. The
    # rescue is deliberately narrow. HttpFetcher already maps Net::OpenTimeout,
    # Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET and
    # OpenSSL::SSL::SSLError to FetchError, so there is nothing left for a broad
    # `rescue StandardError` to catch that we would want caught. Vips::Error sits
    # beside it because a 200 carrying something that is not an image — an error
    # page, a redirect body, a truncated file — is the same event as a failed
    # fetch from this class's point of view, and is the one such event
    # HttpFetcher cannot see.
    # Bounded by CARDS.size rather than by Og::MAX_ARTS, although the two are the
    # same number: this is how many cards the *layout* can draw, and a third art
    # would otherwise be fetched over the network and then indexed off the end of
    # CARDS. The payload builders enforce MAX_ARTS; this enforces the drawing.
    # The loader is named, never sniffed, and that is the other half of what makes
    # .allow_generated_svg! safe. `new_from_buffer(bytes, "")` lets libvips choose by inspecting
    # the bytes, so once the SVG loader is unblocked the *CDN* decides which loader runs on its
    # response — and librsvg is exactly the one upstream has not fuzzed. Measured through that
    # path: a 16000x16000 SVG took 66.8 s and 1160 MB, and 25000x25000 never finished, wedging one
    # of five Puma threads on a single unauthenticated request.
    #
    # Card arts are PNG or JPEG (Limitless serves `…_LG.png`), so the loader is picked from the
    # URL's extension the way CardsController#image already picks a content type, and anything
    # else is refused rather than guessed at. An unrecognised extension raises Vips::Error, which
    # the rescue below turns into "one fewer card" like any other failed art.
    def fetch_arts
      Array(@payload.art_urls).first(CARDS.size).filter_map do |url|
        load_art(HttpFetcher.call(url, open_timeout: ART_OPEN_TIMEOUT,
                                      read_timeout: ART_READ_TIMEOUT), url)
      rescue HttpFetcher::FetchError, Vips::Error
        nil
      end
    end

    def load_art(bytes, url)
      case File.extname(URI.parse(url).path).downcase
      when ".jpg", ".jpeg" then Vips::Image.jpegload_buffer(bytes)
      when ".png"          then Vips::Image.pngload_buffer(bytes)
      else raise Vips::Error, "og: refusing to guess a loader for #{url}"
      end
    end

    # The card's illustration window, filling the frame, blurred.
    #
    # thumbnail_image with an explicit height and crop: :centre rather than the
    # spike's extract_area/embed pair: it is guaranteed to return exactly
    # WIDTH x HEIGHT for any source aspect ratio, where the pair silently
    # produced a short frame for an art proportioned differently from a card.
    def blurred_background(art)
      art_window(art)
        .thumbnail_image(WIDTH, height: HEIGHT, crop: :centre)
        .gaussblur(BLUR_SIGMA)
        .then { |i| with_alpha(i) }
    end

    def art_window(art)
      art.extract_area((art.width * ART_WINDOW[:x]).round,
                       (art.height * ART_WINDOW[:y]).round,
                       (art.width * ART_WINDOW[:width]).round,
                       (art.height * ART_WINDOW[:height]).round)
    end

    def whole_cards(arts)
      arts.each_with_index.map do |art, index|
        spec = CARDS[index]
        image = with_alpha(art.thumbnail_image(CARD_WIDTH))
                  .similarity(angle: spec[:angle], background: [ 0, 0, 0, 0 ])
        { image: image, x: spec[:x], y: spec[:y] }
      end.reverse # the second card sits behind the first
    end

    # --- frames --------------------------------------------------------------

    def photo_frame(art)
      background = blurred_background(art)
      background.composite(scrim_layer, :over)
    end

    def plain_frame
      svg(%(<rect width="#{WIDTH}" height="#{HEIGHT}" fill="#{INK_900}"/>) + rule + mark)
    end

    def scrim_layer
      svg(<<~SVG + rule + mark)
        <defs><linearGradient id="scrim" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#{INK_900}" stop-opacity="#{SCRIM_TOP}"/>
          <stop offset="1" stop-color="#{INK_900}" stop-opacity="#{SCRIM_BOTTOM}"/>
        </linearGradient></defs>
        <rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#scrim)"/>
      SVG
    end

    def rule
      %(<rect x="0" y="0" width="#{WIDTH}" height="#{RULE_HEIGHT}" fill="#{FLARE}"/>)
    end

    def mark
      format(MARK, x: MARK_X, y: MARK_Y, scale: MARK_SIZE / 512.0)
    end

    def svg(body)
      self.class.allow_generated_svg!
      Vips::Image.new_from_buffer(
        %(<svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{HEIGHT}">#{body}</svg>), ""
      )
    end

    # The scrim's contrast guarantee is not computed here any more — see SCRIM_TOP. Og::RendererTest
    # owns the WCAG arithmetic, deliberately: a measurement the renderer performed on itself could
    # only ever agree with itself.

    # --- text ----------------------------------------------------------------

    # The title first, the subtitle in whatever room the title left inside
    # TEXT_COLUMN — so the whole block stays in the frame for a two-line title
    # and for a four-line one alike, rather than for the deck names that happened
    # to be tried.
    def text_layers
      title = title_layer(@payload.title)
      layers = [ { image: title, x: TEXT_COLUMN[:x], y: TEXT_COLUMN[:y] } ]
      return layers if @payload.subtitle.blank?

      y = TEXT_COLUMN[:y] + title.height + SUBTITLE_GAP
      room = TEXT_COLUMN[:y] + TEXT_COLUMN[:height] - y
      return layers if room <= 0

      subtitle = text_layer(@payload.subtitle, size: SUBTITLE_SIZE, weight: "SemiBold",
                                               color: INK_300_RGB, width: TEXT_COLUMN[:width])
      layers << { image: fit(subtitle, room), x: TEXT_COLUMN[:x], y: y }
    end

    def fit(layer, room)
      return layer if layer.width <= TEXT_COLUMN[:width] && layer.height <= room

      layer.extract_area(0, 0, [ layer.width, TEXT_COLUMN[:width] ].min, [ layer.height, room ].min)
    end

    # A deck name is whatever its owner typed, so the title shrinks down
    # TITLE_SIZES until the wrapped block fits the column, and is cropped to it
    # if even the smallest size does not. Nothing raises when text overflows —
    # the glyphs are simply painted past the frame — so the fit has to be
    # arranged rather than trusted.
    #
    # The width is checked as well as the height, and that is not belt and
    # braces: `wrap: :word` breaks at word boundaries only, so a name that is one
    # unbroken 200-character token wraps nowhere and comes back one line tall and
    # thousands of pixels wide — inside TITLE_MAX_HEIGHT, and painted across the
    # whole frame and out the other side.
    def title_layer(string)
      TITLE_SIZES.each do |size|
        layer = text_layer(string, size: size, width: TEXT_COLUMN[:width])
        return layer if fits_column?(layer)
      end

      crop_to_column(text_layer(string, size: TITLE_SIZES.last, width: TEXT_COLUMN[:width]))
    end

    def fits_column?(layer)
      layer.width <= TEXT_COLUMN[:width] && layer.height <= TITLE_MAX_HEIGHT
    end

    def crop_to_column(layer)
      layer.extract_area(0, 0, [ layer.width, TEXT_COLUMN[:width] ].min,
                         [ layer.height, TITLE_MAX_HEIGHT ].min)
    end

    # The one place text is drawn, and therefore the one place `fontfile:` can be
    # forgotten. Text never goes through SVG <text>: librsvg has no line
    # breaking, so a long deck name paints straight past the frame, and the SVG
    # in this class carries geometry only.
    #
    # `fontfile:` is a keyword rather than a hard-coded constant for one reason:
    # the only assertion that can tell Archivo from a silent DejaVu fallback is
    # measuring the same string with the file and without it, and the test does
    # that through this method so it measures the real call.
    def text_layer(string, size:, weight: "ExtraBold", color: PAPER_RGB, width: nil, fontfile: FONT.to_s)
      options = { font: "#{FONT_FAMILY} #{weight} #{size}", dpi: DPI,
                  width: width, wrap: width ? :word : :none, fontfile: fontfile }
      mask = Vips::Image.text(escape_markup(string), **options.compact)
      mask.new_from_image(color).copy(interpretation: :srgb).bandjoin(mask)
    end

    # libvips' `text` hands the string to pango_layout_set_markup, so what looks like a plain-text
    # argument is parsed as Pango markup. Unescaped, that is two live bugs rather than one style
    # question:
    #
    #   * `&` and a bare `<` are markup syntax errors and raise Vips::Error — an unrescued 500 on a
    #     public endpoint. Not hypothetical: the catalogue holds "Anthea & Concordia",
    #     "Billy & O'Nare", "Sordward & Shielbert" and "Gengar & Mimikyu-GX" today, every Tag Team
    #     card ever printed is "X & Y-GX", and "Sword & Shield" is a set name that reaches
    #     Og::CardPayload's subtitle. /og/cards/542 was a 500 before this line existed.
    #   * `<b>bold</b>` in a deck name rendered *as bold*, with the tags swallowed, so the banner's
    #     title was not the deck's name.
    #
    # CGI.escapeHTML covers exactly the five characters GLib's own g_markup_escape_text does, and
    # Pango accepts the entities it produces.
    def escape_markup(string) = CGI.escapeHTML(string.to_s)

    # --- band plumbing -------------------------------------------------------

    def with_alpha(image)
      image.has_alpha? ? image : image.bandjoin(255)
    end


    # JPEG has no alpha channel; flattening explicitly against --ink-900 keeps
    # any transparent edge a rotated card leaves in the brand's dark rather than
    # in libvips' default black.
    def flatten(image)
      return image unless image.has_alpha?

      image.flatten(background: INK_900_RGB)
    end
  end
end
