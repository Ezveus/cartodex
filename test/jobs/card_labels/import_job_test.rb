require "test_helper"

class CardLabels::ImportJobTest < ActiveJob::TestCase
  Printing = CardLabels::LimitlessSearch::Printing
  SearchResult = CardLabels::LimitlessSearch::Result

  setup do
    @user = users(:one)
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type",
                               position: 10, source_query: "is:ace")
    @import = @user.imports.create!(kind: "card_labels", label: "ACE SPEC (is:ace)")
    @original_http = HttpFetcher.method(:call)
    @original_search = CardLabels::LimitlessSearch.method(:call)
    HttpFetcher.define_singleton_method(:call) { |_url| raise "no HTTP in this test" }
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http)
    CardLabels::LimitlessSearch.define_singleton_method(:call, @original_search)
  end

  test "a finished run completes the import and says what it wrote" do
    stub_search([ Printing.new(set_code: "POR", number: "56") ])

    perform

    assert_equal "completed", @import.reload.status
    assert_match "1 card labelled", @import.error_message
  end

  # The receipt has to name every way a run can be partial, because none of them is a failure and
  # all of them change what the report will say.
  #
  # NOPE 1 rather than the brief's ZZZ 999: that pair is already `cards(:standings_marker)`, kept
  # off-limits for every other fixture use by its own comment in cards.yml, so it would resolve as
  # held rather than missing here.
  test "the receipt names the printings not held, the unlisted rows and a count mismatch" do
    CardLabelAssignment.create!(card_label: @label, fingerprint: "doublade_fp", source: "imported")
    stub_search([ Printing.new(set_code: "POR", number: "56"),
                  Printing.new(set_code: "NOPE", number: "1") ], announced_count: 5)

    perform

    receipt = @import.reload.error_message

    assert_match "1 printing not in the catalogue", receipt
    assert_match "NOPE 1", receipt
    assert_match "1 assignment the source no longer lists", receipt
    assert_match "read 2 of an announced 5", receipt
  end

  # Enqueued with ids for exactly this: handed the record, GlobalID raises before #perform is
  # entered and the rescue below never runs, leaving the Import at "pending" forever with no way
  # to clear it — Admin::ImportsController#retry refuses this kind.
  test "a label deleted while the run was queued fails the import instead of hanging it" do
    @label.destroy

    perform

    assert_equal "failed", @import.reload.status
    assert_match "no longer exists", @import.error_message
  end

  test "a fetch failure fails the import with the reason" do
    CardLabels::Importer.define_singleton_method(:call) do |_label, **_options|
      raise HttpFetcher::FetchError, "HTTP 429 for https://limitlesstcg.com/cards"
    end

    perform

    assert_equal "failed", @import.reload.status
    assert_match "HTTP 429", @import.error_message
  ensure
    CardLabels::Importer.singleton_class.remove_method(:call)
  end

  # The Import can be deleted from the admin panel while the run is in flight. That is an ordinary
  # lookup miss, not an error to report — there is nowhere left to report it.
  test "a deleted import ends the run quietly" do
    stub_search([ Printing.new(set_code: "POR", number: "56") ])
    @import.destroy

    assert_nothing_raised { perform }
  end

  private

  def perform = CardLabels::ImportJob.perform_now(@import.id, @label.id, @user.id)

  def stub_search(printings, announced_count: nil)
    result = SearchResult.new(printings: printings, announced_count: announced_count || printings.size)
    CardLabels::LimitlessSearch.define_singleton_method(:call) { |_token| result }
  end
end
