require "test_helper"

class CardSets::RescrapeJobTest < ActiveSupport::TestCase
  setup do
    @card_set = card_sets(:por)
    Card.where(set_name: "POR").update_all(card_set_id: @card_set.id)
    @cards = @card_set.cards.reload.to_a
    @original = Cards::Fetcher.method(:call)
    @fetcher_calls = []
    Cards::Fetcher.define_singleton_method(:call) do |url, **opts|
      Thread.current[:rescrape_test_calls] << { url: url, force: opts[:force] }
      nil
    end
    Thread.current[:rescrape_test_calls] = @fetcher_calls
  end

  teardown do
    Cards::Fetcher.define_singleton_method(:call, @original)
    Thread.current[:rescrape_test_calls] = nil
  end

  test "calls Cards::Fetcher with force: true for every card in the set" do
    CardSets::RescrapeJob.perform_now(@card_set.id)

    assert_equal @cards.size, @fetcher_calls.size
    assert @fetcher_calls.all? { |c| c[:force] == true }
    assert @fetcher_calls.all? { |c| c[:url].start_with?("https://limitlesstcg.com/cards/POR/") }
  end

  test "continues iterating when one card fetch fails" do
    Cards::Fetcher.define_singleton_method(:call) do |url, **opts|
      raise "boom" if url.end_with?("/56")

      Thread.current[:rescrape_test_calls] << { url: url, force: opts[:force] }
    end

    assert_nothing_raised do
      CardSets::RescrapeJob.perform_now(@card_set.id)
    end
    refute_empty @fetcher_calls
  end

  test "forgets the cached filter values, which a forced rescrape can change" do
    with_real_cache do
      Card.filter_values # populate

      CardSets::RescrapeJob.perform_now(@card_set.id)

      # `force: true` is the only thing in the app that rewrites an existing card's text, so
      # it is the only other way a rarity or regulation mark can change.
      assert_operator count_queries { Card.filter_values }, :>, 0,
        "expected the rescrape to have dropped the cached lists"
    end
  end

  # :null_store in test makes every fetch a miss, so a real store has to stand in or the
  # assertion is vacuous.
  def with_real_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    yield
  ensure
    Rails.cache = original
  end
end
