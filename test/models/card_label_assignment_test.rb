require "test_helper"

class CardLabelAssignmentTest < ActiveSupport::TestCase
  setup do
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
  end

  # The fingerprint is the identity. A blank one would be a row the report can never join to and
  # that the UNIQUE key would let through once per label.
  test "a blank fingerprint is refused" do
    assert_not @label.assignments.new(fingerprint: "", source: "imported").valid?
    assert_not @label.assignments.new(fingerprint: nil, source: "imported").valid?
  end

  test "one decision per label and fingerprint" do
    @label.assignments.create!(fingerprint: "fp", source: "imported")
    second = @label.assignments.new(fingerprint: "fp", source: "curated")

    assert_not second.valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      second.save(validate: false)
    end
  end

  test "a source outside the vocabulary is refused" do
    assert_not @label.assignments.new(fingerprint: "fp", source: "guessed").valid?
  end

  # `active` is what every reader of this table uses: a rejected row is a human saying no, and it
  # must survive rather than being deleted, or the next suggestion run proposes it again.
  test "active excludes rejected rows" do
    kept = @label.assignments.create!(fingerprint: "kept", source: "curated")
    @label.assignments.create!(fingerprint: "refused", source: "curated", rejected: true)

    assert_equal [ kept ], @label.assignments.active.to_a
  end

  # The card is the printing the decision came from, not the decision itself: deleting it from the
  # admin panel must not delete what a human decided about the card it was a printing of.
  test "deleting the card leaves the assignment standing" do
    card = cards(:honedge)
    assignment = @label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")

    card.destroy

    assert_nil assignment.reload.card_id
    assert_equal "honedge_fp", assignment.fingerprint
  end

  # Three sources, three governances: the suggester rewrites only its own rows, the importer only
  # its own, and a curated decision outranks both. Each of those rules is a scope away from being
  # written wrong, so each scope selects its own rows and nothing else.
  test "the source scopes select their own rows and nothing else" do
    label = CardLabel.create!(slug: "gust", name: "Gust", family: "role", position: 30)
    imported = label.assignments.create!(fingerprint: "a", source: "imported")
    suggested = label.assignments.create!(fingerprint: "b", source: "suggested")
    curated = label.assignments.create!(fingerprint: "c", source: "curated")

    assert_equal [ imported.id ], label.assignments.imported.pluck(:id)
    assert_equal [ suggested.id ], label.assignments.suggested.pluck(:id)
    assert_equal [ curated.id ], label.assignments.curated.pluck(:id)
  end
end
