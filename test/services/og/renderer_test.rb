require "test_helper"
require "vips"

class Og::RendererTest < ActiveSupport::TestCase
  ART_URLS = [ "https://limitlesstcg.com/img/one.png", "https://limitlesstcg.com/img/two.png" ].freeze

  # Deliberately unroutable: port 1 on the loopback, which nothing listens on, so
  # the real HttpFetcher raises Errno::ECONNREFUSED and maps it to FetchError.
  UNROUTABLE_URL = "http://127.0.0.1:1/one.png".freeze

  # Longer than any deck name a human types, and with spaces, so `wrap: :word`
  # has somewhere to break.
  LONG_TITLE = ("Raging Bolt ex / Teal Mask Ogerpon ex with a Dragapult ex " * 4).strip.freeze

  # The case `wrap: :word` cannot break at all: one token, no spaces. A title
  # this shape wraps nowhere and comes back one line tall and thousands of pixels
  # wide, which is inside TITLE_MAX_HEIGHT and outside the frame.
  UNBREAKABLE_TITLE = ("Rulebox" * 30).freeze

  # The right-hand region the whole cards land in, in the composed frame. Used to
  # tell a photographed banner from the branded one by its pixels rather than by
  # the fact that both are valid JPEGs of the right size.
  ART_REGION = { x: 660, y: 150, width: 540, height: 460 }.freeze

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @fetched = []
    @fetch_options = []
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  # --- the output itself ---------------------------------------------------

  test "renders a JPEG of exactly 1200x630" do
    stub_arts(ART_URLS => flat_art([ 40, 90, 160 ]))

    bytes = Og::Renderer.call(payload(art_urls: ART_URLS)).bytes

    # Read back through Vips rather than trusting the writer: the WIDTH/HEIGHT
    # constants describe the SVG frame, and a composite placed past its edge, or
    # a background of the wrong aspect, changes the image without changing them.
    image = Vips::Image.new_from_buffer(bytes, "")
    assert_equal Og::Renderer::WIDTH, image.width
    assert_equal Og::Renderer::HEIGHT, image.height
    assert_equal "jpegload_buffer", image.get("vips-loader"),
                 "the banner must be JPEG — a PNG of the same image weighs 443 KB against 92.8 KB"
  end

  # --- the title cannot leave its column ----------------------------------

  test "a title far longer than any deck name stays inside TEXT_COLUMN" do
    renderer = Og::Renderer.new(payload(title: LONG_TITLE))

    layers = renderer.send(:text_layers)
    title = layers.first[:image]

    assert_operator title.width, :<=, Og::Renderer::TEXT_COLUMN[:width]
    assert_operator title.height, :<=, Og::Renderer::TITLE_MAX_HEIGHT
    assert_operator bottom_of(layers.last), :<=,
                    Og::Renderer::TEXT_COLUMN[:y] + Og::Renderer::TEXT_COLUMN[:height]
  end

  test "a title with no word break to wrap at stays inside TEXT_COLUMN" do
    renderer = Og::Renderer.new(payload(title: UNBREAKABLE_TITLE))

    title = renderer.send(:title_layer, UNBREAKABLE_TITLE)

    assert_operator title.width, :<=, Og::Renderer::TEXT_COLUMN[:width],
                    "`wrap: :word` cannot break one long token, so the width has to be enforced"
    assert_operator title.height, :<=, Og::Renderer::TITLE_MAX_HEIGHT
  end

  test "the whole text block stays inside TEXT_COLUMN when the subtitle is long too" do
    renderer = Og::Renderer.new(payload(title: LONG_TITLE, subtitle: LONG_TITLE))

    layers = renderer.send(:text_layers)

    assert_equal 2, layers.size
    layers.each do |layer|
      assert_operator layer[:x] + layer[:image].width, :<=,
                      Og::Renderer::TEXT_COLUMN[:x] + Og::Renderer::TEXT_COLUMN[:width]
      assert_operator bottom_of(layer), :<=,
                      Og::Renderer::TEXT_COLUMN[:y] + Og::Renderer::TEXT_COLUMN[:height]
    end
  end

  # --- the brand font --------------------------------------------------------

  test "text is drawn from the repository's Archivo, not from a silent fallback" do
    renderer = Og::Renderer.new(payload)
    string = "Raging Bolt ex / Teal Mask Ogerpon ex"

    layer = renderer.send(:text_layer, string, size: 76, width: 520)

    # Golden metrics, and they are the only order-independent way to ask this question.
    #
    # The obvious test — render with `fontfile:` and again without it, and assert the widths
    # differ — cannot work, and it took a red test to find out why: `fontfile:` registers the
    # file with fontconfig for the **whole process**, so once any call has passed it, every later
    # call resolves "Archivo" without it. Measured in the container: with the fontfile 437x320,
    # without it 437x320, and DejaVu 492x342. Nothing was ignored; the comparison was blind.
    #
    # So this pins the outcome instead. 437x320 is Archivo rendering this string at 76pt in a
    # 520px column at 72dpi, measured from vendor/fonts/Archivo.ttf; 492x342 is what the same
    # request produces when it falls back to DejaVu, which is the failure this guards. Replacing
    # the committed font is the one thing that legitimately moves these numbers, and it should
    # turn this red so somebody re-measures rather than shipping a silently different banner.
    assert_equal [ 437, 320 ], [ layer.width, layer.height ],
                 "the title is no longer Archivo at these metrics — DejaVu measures 492x342 here"
    assert_path_exists Og::Renderer::FONT, "vendor/fonts/Archivo.ttf must be committed"
  end

  # --- the scrim's contrast guarantee ---------------------------------------

  # The scrim is a fixed SCRIM_TOP -> SCRIM_BOTTOM gradient, and this is the assertion that
  # replaced the adaptive ladder it used to have. The ladder walked five opacities until the text
  # column cleared CONTRAST_TARGET and could never move off its first rung, because TEXT_COLUMN
  # sits low in the frame where the gradient is nearly opaque — so it was a mechanism in
  # appearance only. Deleting it kept the approved look; this keeps the promise.
  #
  # Worst case first: a flat white art is the palest ground a card illustration could ever
  # present, so if the title clears the target on that it clears it on every real one. The three
  # measured values on this geometry are white 10.67:1, light grey 12.23:1, flat black 17.96:1 —
  # note that white is the *worst* of the three and still more than doubles the target.
  #
  # What this goes red on: moving TEXT_COLUMN up into the lighter part of the gradient, lowering
  # SCRIM_BOTTOM, or removing the scrim altogether. Which is the whole point — those are exactly
  # the edits that would quietly make a banner illegible.
  test "the title clears the contrast target on the palest artwork there could be" do
    renderer = Og::Renderer.new(payload)
    background = renderer.send(:blurred_background, image_of(flat_art([ 255, 255, 255 ])))

    assert_operator measured_contrast(renderer, background), :>=, Og::Renderer::CONTRAST_TARGET
  end

  test "and on a dark one, which is the common case" do
    renderer = Og::Renderer.new(payload)
    background = renderer.send(:blurred_background, image_of(flat_art([ 10, 12, 20 ])))

    assert_operator measured_contrast(renderer, background), :>=, Og::Renderer::CONTRAST_TARGET
  end

  # --- 0, 1 and 2 arts -------------------------------------------------------

  test "renders with no art at all" do
    assert_banner Og::Renderer.call(payload(art_urls: [])).bytes
  end

  test "renders with one art" do
    stub_arts(ART_URLS.first(1) => flat_art([ 230, 90, 40 ]))

    assert_banner Og::Renderer.call(payload(art_urls: ART_URLS.first(1))).bytes
  end

  test "renders with two arts" do
    stub_arts(ART_URLS => flat_art([ 230, 90, 40 ]))

    assert_banner Og::Renderer.call(payload(art_urls: ART_URLS)).bytes

    assert_equal ART_URLS, @fetched, "both arts are fetched, once each"
  end

  test "at most two arts are fetched however many the payload carries" do
    urls = ART_URLS + [ "https://limitlesstcg.com/img/three.png" ]
    stub_arts(urls => flat_art([ 230, 90, 40 ]))

    Og::Renderer.call(payload(art_urls: urls)).bytes

    assert_equal ART_URLS, @fetched, "the layout holds two cards, so the third is never fetched"
  end

  test "two arts put the cards on the frame, not merely a valid JPEG of the right size" do
    stub_arts(ART_URLS => flat_art([ 230, 90, 40 ]))
    photographed = Og::Renderer.call(payload(art_urls: ART_URLS)).bytes
    branded = Og::Renderer.call(payload(art_urls: [])).bytes

    # The whole compositing half of this class can be broken while every other
    # test here passes, because a broken composite still writes a 1200x630 JPEG.
    # Only the pixels say the cards arrived.
    assert_operator (mean_luminance(photographed, ART_REGION) - mean_luminance(branded, ART_REGION)).abs,
                    :>, 20,
                    "the art region of a two-art banner must not look like the branded banner's"
  end

  # --- a failed fetch --------------------------------------------------------

  test "an unroutable art degrades to the branded banner" do
    # No stub on purpose. The house idiom (HttpFetcher.define_singleton_method)
    # bypasses HttpFetcher's own rescues, so a test built on it would only prove
    # the renderer catches whatever class the stub chose to raise. This one runs
    # the real fetcher against a real closed port, so the exception really is the
    # Errno::ECONNREFUSED that HttpFetcher maps to FetchError.
    degraded = Og::Renderer.call(payload(art_urls: [ UNROUTABLE_URL ])).bytes
    branded = Og::Renderer.call(payload(art_urls: [])).bytes

    assert_banner degraded
    assert_in_delta mean_luminance(branded, ART_REGION), mean_luminance(degraded, ART_REGION), 1.0,
                    "a fetch failure must fall back to the branded banner, not to a half-drawn one"
  end

  test "one failed art of two still renders the other" do
    # Stubbed rather than unroutable, because what is under test here is the
    # filter_map — one nil among two arts costing one card and not the
    # photograph — and not which exception class arrives.
    stub_arts(ART_URLS.first(1) => flat_art([ 230, 90, 40 ]))
    with_one = Og::Renderer.call(payload(art_urls: ART_URLS)).bytes
    branded = Og::Renderer.call(payload(art_urls: [])).bytes

    assert_banner with_one
    assert_operator (mean_luminance(with_one, ART_REGION) - mean_luminance(branded, ART_REGION)).abs,
                    :>, 20,
                    "one unreachable art must cost one card, not the whole photograph"
  end

  test "a 200 carrying something that is not an image degrades rather than raising" do
    HttpFetcher.define_singleton_method(:call) { |_url, **| "<html>404 not found</html>" }

    assert_banner Og::Renderer.call(payload(art_urls: ART_URLS)).bytes
  end

  # --- Pango markup, and the 500 it was ------------------------------------

  # libvips' `text` hands its argument to pango_layout_set_markup, so a plain-looking string is
  # parsed as markup. Unescaped, `&` and a bare `<` are syntax errors that raise Vips::Error, which
  # nothing rescues — an unauthenticated 500 on a public endpoint. Not a hypothetical input: the
  # catalogue holds "Anthea & Concordia", "Billy & O'Nare", "Sordward & Shielbert" and
  # "Gengar & Mimikyu-GX" today, every Tag Team card ever printed is "X & Y-GX", and
  # "Sword & Shield" is a set name that reaches Og::CardPayload's subtitle. None of the fifteen
  # sabotages run against this feature could have found it, because no test rendered one of those
  # characters.
  test "an ampersand in a title renders instead of raising" do
    assert_banner Og::Renderer.call(payload(title: "Anthea & Concordia")).bytes
  end

  test "a bare angle bracket in a title renders instead of raising" do
    assert_banner Og::Renderer.call(payload(title: "Gholdengo <3", subtitle: "60 cards & counting")).bytes
  end

  # The other half of the same bug, and the silent half: markup was *interpreted*, so a deck named
  # "<b>Mill</b>" drew as bold with the tags swallowed and the banner's title was not the deck's
  # name. The two layers must differ, because one really has six more characters to draw.
  test "markup in a title is printed, not obeyed" do
    renderer = Og::Renderer.new(payload)
    plain = renderer.send(:text_layer, "Mill", size: 60, width: 520)
    marked = renderer.send(:text_layer, "<b>Mill</b>", size: 60, width: 520)

    refute_equal plain.width, marked.width,
                 "identical widths mean the tags were parsed as markup and swallowed"
  end

  # Not a behavioural assertion, and deliberately so: proving the timeouts by behaviour needs a
  # socket that accepts and never answers, which is a test that takes as long as the timeout it is
  # checking. What it guards is real — HttpFetcher's own defaults are 10 and 30, fetch_arts makes
  # two serial calls inside one web request, and a hung image host was measured holding a Puma
  # thread for 120.4 s while the request still *succeeded*, degraded to the artless banner, so
  # nothing surfaced it. A request budget cannot bound thread-seconds. Sabotaged: dropping the
  # keywords from the call site leaves every other test in this file green.
  test "art fetches are bounded far below HttpFetcher's own defaults" do
    stub_arts(ART_URLS => flat_art([ 40, 90, 160 ]))

    Og::Renderer.call(payload(art_urls: ART_URLS))

    assert_equal 2, @fetch_options.size
    @fetch_options.each do |options|
      assert_equal Og::Renderer::ART_OPEN_TIMEOUT, options[:open_timeout]
      assert_equal Og::Renderer::ART_READ_TIMEOUT, options[:read_timeout]
    end
    assert_operator Og::Renderer::ART_OPEN_TIMEOUT, :<, HttpFetcher::OPEN_TIMEOUT
    assert_operator Og::Renderer::ART_READ_TIMEOUT, :<, HttpFetcher::READ_TIMEOUT
  end

  # --- the loader is named, never sniffed ----------------------------------

  # `new_from_buffer(bytes, "")` lets libvips choose a loader by inspecting the bytes, so with
  # svgload unblocked the CDN would decide which loader runs on its own response — and a
  # 16000x16000 SVG through librsvg was measured at 66.8 s and 1160 MB, wedging one of five Puma
  # threads on a single request. The loader now comes from the URL's extension, and anything else
  # is refused rather than guessed at.
  test "an art whose bytes are an SVG is refused rather than decoded" do
    svg = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="4000" height="4000">
        <rect width="4000" height="4000" fill="#ff0000"/>
      </svg>
    SVG
    stub_arts("https://example.test/art.png" => svg)

    result = Og::Renderer.call(payload(art_urls: [ "https://example.test/art.png" ]))

    refute result.complete, "an art that could not be decoded is a degraded render"
    assert_banner result.bytes
  end

  test "an art at an extension the renderer does not know is refused" do
    stub_arts("https://example.test/art.tiff" => "whatever".b)

    result = Og::Renderer.call(payload(art_urls: [ "https://example.test/art.tiff" ]))

    refute result.complete
  end

  # --- Result#complete -----------------------------------------------------

  # Og::Cache reads this to decide whether to *store* a render, so it is the difference between a
  # transient CDN failure costing one preview and costing that deck its artwork permanently.
  test "complete says whether every art the payload asked for resolved" do
    stub_arts(ART_URLS => flat_art([ 40, 90, 160 ]))

    assert Og::Renderer.call(payload(art_urls: [])).complete,
           "a payload with no artwork asked for nothing and got it"
    assert Og::Renderer.call(payload(art_urls: ART_URLS)).complete
    refute Og::Renderer.call(payload(art_urls: [ UNROUTABLE_URL ])).complete
    refute Og::Renderer.call(payload(art_urls: [ ART_URLS.first, UNROUTABLE_URL ])).complete,
           "one art of two failing is still incomplete"
  end

  private

  def payload(kind: "deck", key: "abc123", title: "Raging Bolt ex / Teal Mask Ogerpon ex",
              subtitle: "60 cards · Standard TEF-PBL", art_urls: [], digest: "deadbeefdeadbeef")
    Og::Payload.new(kind: kind, key: key, title: title, subtitle: subtitle,
                    art_urls: art_urls, digest: digest)
  end

  # Records what was asked for in @fetched, so a test can assert on round trips
  # as well as on pixels. House idiom, per test/services/cards/fetcher_cache_test.rb.
  def stub_arts(bodies_by_urls)
    served = bodies_by_urls.flat_map { |urls, body| Array(urls).map { |url| [ url, body ] } }.to_h
    fetched = @fetched
    # The keywords are captured rather than swallowed: Og::Renderer passes its own short
    # open/read timeouts, and a stub taking only |url| would ArgumentError, which is a confusing
    # way to learn about a keyword.
    options = @fetch_options
    HttpFetcher.define_singleton_method(:call) { |url, **kwargs|
      fetched << url
      options << kwargs
      served.fetch(url) { raise HttpFetcher::FetchError, "Unexpected URL: #{url}" }
    }
  end

  # A flat 460x640 PNG — the resolution Limitless serves. Flat on purpose: the
  # scrim tests need to know exactly how pale the artwork is, and a real card is
  # a distribution rather than a value.
  def flat_art(rgb)
    Vips::Image.black(460, 640).new_from_image(rgb).copy(interpretation: :srgb).write_to_buffer(".png")
  end

  def image_of(bytes)
    Vips::Image.new_from_buffer(bytes, "")
  end

  def assert_banner(bytes)
    image = Vips::Image.new_from_buffer(bytes, "")
    assert_equal [ Og::Renderer::WIDTH, Og::Renderer::HEIGHT ], [ image.width, image.height ]
  end

  def mean_luminance(bytes, region)
    Vips::Image.new_from_buffer(bytes, "")
      .extract_area(region[:x], region[:y], region[:width], region[:height])
      .colourspace(:b_w)
      .avg
  end

  def bottom_of(layer)
    layer[:y] + layer[:image].height
  end

  # The WCAG 2.1 contrast ratio of --paper against the composed background, in the region the
  # title lands in. The arithmetic lives here and not in the renderer on purpose: a measurement
  # the renderer performed on itself could only ever agree with itself. The text is deliberately
  # not composited — paper-coloured glyphs would raise the region's mean and the number would then
  # describe the text rather than the ground under it.
  def measured_contrast(renderer, background)
    window = background
      .composite(renderer.send(:scrim_layer), :over)
      .extract_area(*Og::Renderer::TEXT_COLUMN.values_at(:x, :y, :width, :height))
    grey = window.extract_band(0, n: 3).copy(interpretation: :srgb).colourspace(:b_w).avg

    contrast(relative_luminance([ 247, 248, 250 ]), relative_luminance([ grey ] * 3))
  end

  def contrast(one, other)
    lighter, darker = [ one, other ].minmax.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  def relative_luminance(rgb)
    r, g, b = rgb.map do |channel|
      value = channel / 255.0
      value <= 0.03928 ? value / 12.92 : (((value + 0.055) / 1.055)**2.4)
    end
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end
end
