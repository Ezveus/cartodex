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
    # The fake ignores nothing: it would still pass all of this suite reading @label.slug instead
    # of source_query, and then fail in production against LimitlessSearch::TOKEN_RE.
    assert_equal "is:ace", @search_token
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

  # The whole point of `source`. A human decision outranks the source, including a refusal — and
  # the obvious-looking "refresh the printing pointer" mutant (`assignment.update!(card:
  # printings.first)` beside the persisted? guard) leaves source, rejected and created all
  # correct, so this asserts the *whole row*, not the two fields that mutant happens to spare.
  test "it never touches a curated decision" do
    assignment = @label.assignments.create!(fingerprint: "honedge_fp", source: "curated", rejected: true)

    result = nil
    assert_no_changes -> { assignment.reload.attributes } do
      result = import([ printing_for(@honedge) ])
    end

    assert_equal 0, result.created
  end

  # Stage 2's suggester rewrites its own suggested rows; the importer must never race it either.
  test "it never touches a suggested decision" do
    assignment = @label.assignments.create!(fingerprint: "honedge_fp", source: "suggested")

    result = nil
    assert_no_changes -> { assignment.reload.attributes } do
      result = import([ printing_for(@honedge) ])
    end

    assert_equal 0, result.created
  end

  # Reported, never deleted: a page truncated by a transport failure would otherwise depopulate a
  # label, and an admin would have no way to tell that from the source dropping a card. The row
  # assertions catch a soft-deleting mutant (`…update_all(rejected: true)` instead of `pluck`) that
  # would otherwise still report ["doublade_fp"] and still count 2 rows while quietly rejecting one.
  test "an assignment the source no longer lists is reported and kept" do
    import([ printing_for(@honedge), printing_for(@doublade) ])

    result = import([ printing_for(@honedge) ])

    assert_equal [ "doublade_fp" ], result.unlisted_fingerprints
    assert_equal 2, @label.assignments.count

    doublade_assignment = @label.assignments.find_by(fingerprint: "doublade_fp")
    assert_equal "imported", doublade_assignment.source
    assert_not doublade_assignment.rejected?
  end

  # Task 5 renders unlisted_fingerprints to an admin who acts on it, so leaking another label's row
  # into it is exactly what the card_label_id scope on @label.assignments exists to prevent — and
  # nothing in the suite otherwise builds a second label to prove that scope is load-bearing.
  test "an unlisted row belonging to another label is never reported here" do
    other_label = CardLabel.create!(slug: "tera", name: "Tera", family: "type",
                                    position: 20, source_query: "is:tera")
    other_label.assignments.create!(fingerprint: "doublade_fp", source: "imported")

    result = import([ printing_for(@honedge) ])

    assert_equal [], result.unlisted_fingerprints
  end

  # The other half of the same scope: a curated row this run does not list is a human's decision,
  # not a stray — reporting it as unlisted is exactly the rule the `.imported` scope exists to
  # prevent, and nothing else in the suite builds a curated row that a run's printings simply omit.
  test "a curated decision this run does not list is never reported as unlisted" do
    @label.assignments.create!(fingerprint: "doublade_fp", source: "curated", rejected: true)

    result = import([ printing_for(@honedge) ])

    assert_equal [], result.unlisted_fingerprints
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

  # LimitlessSearch itself never returns this (a ParseError fires first on an empty grid), but
  # `search:` exists precisely so another reader can be injected, and that reader carries no such
  # guard — the empty OR-list this used to build was invalid SQL on its own, with no printings
  # involved to make it a plausible admin-facing failure.
  test "an empty result from the source is a no-op, not a crash" do
    result = import([])

    assert_equal 0, result.created
    assert_equal 0, result.already_present
    assert_equal [], result.missing_printings
    assert_equal [], result.unfingerprinted
    assert_equal [], result.unlisted_fingerprints
  end

  # An empty result is not special-cased into silence: if the source affirmatively lists nothing,
  # every row already on the label genuinely is no longer listed, and the same "report, never
  # delete" rule applies at that edge rather than a different one — `where.not(fingerprint: [])`
  # is `1=1`, so this is the honest reading of an empty page rather than an accident of the guard.
  test "an empty source result reports every currently-imported row as unlisted, keeping them" do
    import([ printing_for(@honedge), printing_for(@doublade) ])

    result = import([])

    assert_equal %w[doublade_fp honedge_fp].sort, result.unlisted_fingerprints.sort
    assert_equal 2, @label.assignments.count
  end

  private

  def printing_for(card) = Printing.new(set_code: card.set_name, number: card.set_number)

  def import(printings, announced_count: nil)
    test = self
    search = Class.new do
      define_singleton_method(:call) do |token|
        test.instance_variable_set(:@search_token, token)
        SearchResult.new(printings: printings, announced_count: announced_count || printings.size)
      end
    end

    CardLabels::Importer.call(@label, search: search)
  end
end
