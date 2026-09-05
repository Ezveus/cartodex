require "test_helper"

class CardLabels::ImporterTest < ActiveSupport::TestCase
  Printing = CardLabels::LimitlessSearch::Printing
  SearchResult = CardLabels::LimitlessSearch::Result

  setup do
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type",
                               position: 10, source_query: "is:ace")
    @honedge = cards(:honedge)
    @doublade = cards(:doublade)
  end

  test "it labels every printing the catalogue holds, keyed on the fingerprint" do
    result = import([ printing_for(@honedge), printing_for(@doublade) ])

    assert_equal 2, result.created
    assert_equal %w[doublade_fp honedge_fp].sort,
      @label.assignments.pluck(:fingerprint).sort
    assert_equal [ "imported" ], @label.assignments.pluck(:source).uniq
    assert_equal @honedge.id, @label.assignments.find_by(fingerprint: "honedge_fp").card_id
  end

  # A printing Limitless lists and the catalogue lacks is counted, never created: acquiring cards
  # is CardSets::Importer's job, and since #121 a known printing is never re-scraped.
  #
  # NOPE 1 rather than the brief's ZZZ 999: that pair is already `cards(:standings_marker)`, kept
  # off-limits for every other fixture use by its own comment in cards.yml, so it is not actually
  # a missing printing here.
  test "a printing the catalogue does not hold is counted, not created" do
    assert_no_difference "Card.count" do
      @result = import([ printing_for(@honedge), Printing.new(set_code: "NOPE", number: "1") ])
    end

    assert_equal 1, @result.created
    assert_equal [ "NOPE 1" ], @result.missing_printings
  end

  # A second run must be a no-op, not a rewrite: it is the ordinary way an admin picks up a set
  # that landed since the last one.
  test "a second run creates nothing and reports what was already there" do
    import([ printing_for(@honedge) ])

    assert_no_difference "CardLabelAssignment.count" do
      @result = import([ printing_for(@honedge) ])
    end

    assert_equal 0, @result.created
    assert_equal 1, @result.already_present
  end

  # The whole point of `source`. A human decision outranks the source, including a refusal.
  test "it never touches a curated decision" do
    @label.assignments.create!(fingerprint: "honedge_fp", source: "curated", rejected: true)

    result = import([ printing_for(@honedge) ])

    assignment = @label.assignments.find_by(fingerprint: "honedge_fp")

    assert_equal "curated", assignment.source
    assert assignment.rejected?
    assert_equal 0, result.created
  end

  # Reported, never deleted: a page truncated by a transport failure would otherwise depopulate a
  # label, and an admin would have no way to tell that from the source dropping a card.
  test "an assignment the source no longer lists is reported and kept" do
    import([ printing_for(@honedge), printing_for(@doublade) ])

    result = import([ printing_for(@honedge) ])

    assert_equal [ "doublade_fp" ], result.unlisted_fingerprints
    assert_equal 2, @label.assignments.count
  end

  # compute_fingerprint is a before_save, so only a callback-bypassing write produces this. The
  # report keys such a card under its own id and can never join it to a label, so labelling it
  # would write a row nothing can read.
  test "a card with no fingerprint is skipped and named" do
    @honedge.update_column(:fingerprint, nil)

    result = import([ printing_for(@honedge) ])

    assert_equal 0, result.created
    assert_equal [ "POR 56" ], result.unfingerprinted
  end

  # Two printings of one card are one card. Both are recorded as the source of the decision only
  # once, and nothing raises on the UNIQUE key.
  test "two printings sharing a fingerprint produce one assignment" do
    result = import([ printing_for(cards(:budew_pre)), printing_for(cards(:budew_asc)) ])

    assert_equal 1, result.created
    assert_equal [ "budew_shared" ], @label.assignments.pluck(:fingerprint)
  end

  test "it carries the counts the receipt needs" do
    result = import([ printing_for(@honedge) ], announced_count: 4)

    assert_equal 4, result.announced_count
    assert_equal 1, result.read_count
    assert_not result.complete?
  end

  private

  def printing_for(card) = Printing.new(set_code: card.set_name, number: card.set_number)

  def import(printings, announced_count: nil)
    search = Class.new do
      define_singleton_method(:call) do |_token|
        SearchResult.new(printings: printings, announced_count: announced_count || printings.size)
      end
    end

    CardLabels::Importer.call(@label, search: search)
  end
end
