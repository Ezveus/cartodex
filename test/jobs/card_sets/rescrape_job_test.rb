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
end
