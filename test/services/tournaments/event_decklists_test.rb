require "test_helper"

class Tournaments::EventDecklistsTest < ActiveSupport::TestCase
  BASE = "https://limitlesstcg.com".freeze
  MASTERS_URL = "#{BASE}/tournaments/577/decklists".freeze
  SENIOR_URL = "#{BASE}/tournaments/577/SR/decklists".freeze

  def self.fixture(name) = File.read(Rails.root.join("test/fixtures/files/limitless/#{name}.html")).freeze

  MASTERS_577 = fixture("tournament_577_masters_decklists")
  SENIOR_577 = fixture("tournament_577_senior_decklists")
  MASTERS_563 = fixture("tournament_563_masters_decklists")

  PAGES_577 = { MASTERS_URL => MASTERS_577, SENIOR_URL => SENIOR_577 }.freeze

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @http_calls = []
    stub_pages(PAGES_577)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  # The whole point of the service, and the reason a whole event costs six requests instead of
  # 575: one page carries every list of its division. Counting the fetches is what pins it — the
  # texts alone are just as correct under an implementation that goes and gets each one.
  test "answers every row of a division out of one fetch" do
    store = Tournaments::EventDecklists.new(577)

    texts = [ 1, 127, 351, 559 ].map { |rank| store.call("577/masters/#{rank}") }

    assert_equal [ MASTERS_URL ], @http_calls
    assert_equal 4, texts.uniq.size
    texts.each { |text| assert_equal 60, text.lines.sum { |line| line.to_i } }
    assert_match(/Mega Kangaskhan ex MEG /, texts.first)
  end

  # Lazily, and once. A division nobody asks about is a page nobody fetches — 563 publishes no
  # Junior decklists at all, and an event whose rows are all Masters must not pay for three.
  test "fetches a division page only when a row of that division asks, and only once" do
    store = Tournaments::EventDecklists.new(577)
    assert_empty @http_calls

    store.call("577/masters/1")
    assert_equal [ MASTERS_URL ], @http_calls

    store.call("577/senior/2")
    assert_equal [ MASTERS_URL, SENIOR_URL ], @http_calls

    store.call("577/senior/3")
    store.call("577/masters/127")
    assert_equal [ MASTERS_URL, SENIOR_URL ], @http_calls
  end

  # **Measured on the committed captures, and it is not what the plan assumed.** On 577 every one
  # of the 559 rows published a list, so `data-target="decklist-N"` and the row's `data-rank` are
  # the same number and nothing can tell them apart. On 563 they come apart: six of ten rows
  # published, and the third block reads `data-target="decklist-3"` while its toggle says
  # "6th Kevin Krueger" — so the attribute is the block's index among the *published* lists. Keyed
  # on it, rank 6's Crustle list is handed to rank 3, who played Rocket's Mewtwo. The rank in the
  # toggle is the only thing on the page that names the row.
  test "keys a block on the rank its toggle states, not on its position among the published lists" do
    stub_pages("#{BASE}/tournaments/563/decklists" => MASTERS_563)
    store = Tournaments::EventDecklists.new(563)

    assert_match(/ Crustle /, store.call("563/masters/6"))

    # Rank 3 published nothing; the third block belongs to rank 6 and must not answer for them.
    assert_raises(Tournaments::EventDecklists::ParseError) { store.call("563/masters/3") }
  end

  # A row that links a list the decklists page does not carry means the two pages disagree. The
  # importer catches it per row: the standing is written and counted before the list is attached,
  # so the placement survives and the reason is named in the run's report — which returning nil
  # would not be, since StandingsImporter#resolve_printings would meet it as a NoMethodError.
  test "refuses a rank the division's decklists page does not publish, and names it" do
    store = Tournaments::EventDecklists.new(577)

    error = assert_raises(Tournaments::EventDecklists::ParseError) { store.call("577/masters/253") }

    assert_match(/253/, error.message)
    assert_match(%r{/tournaments/577/decklists}, error.message)
  end

  test "refuses a key that names another tournament or a division it cannot read" do
    store = Tournaments::EventDecklists.new(577)

    assert_raises(ArgumentError) { store.call("563/masters/1") }
    assert_raises(ArgumentError) { store.call("577/seniors/1") }
    assert_raises(ArgumentError) { store.call("577/masters/x") }
    assert_empty @http_calls
  end

  # The id reaches three URLs, so it is narrowed in the constructor like every other interpolated
  # segment in this namespace.
  test "refuses a tournament id that is not a number" do
    assert_raises(ArgumentError) { Tournaments::EventDecklists.new("577/../563") }
  end

  # A page whose blocks exist but whose ranks are unreadable is a layout change, and every row of
  # that division would otherwise import as a standing with no list and nothing said anywhere.
  test "refuses a decklists page whose blocks name no rank at all" do
    stub_pages(MASTERS_URL => MASTERS_577.gsub(/>\d+(?:st|nd|rd|th) /, ">"))
    store = Tournaments::EventDecklists.new(577)

    error = assert_raises(Tournaments::EventDecklists::ParseError) { store.call("577/masters/1") }

    assert_match(%r{/tournaments/577/decklists}, error.message)
  end

  private

  def stub_pages(pages)
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      raise HttpFetcher::FetchError, "HTTP 404 for #{url}" unless pages.key?(url)

      pages.fetch(url)
    }
  end
end
