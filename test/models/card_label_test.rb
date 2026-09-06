require "test_helper"

class CardLabelTest < ActiveSupport::TestCase
  test "a slug is unique across families" do
    CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    duplicate = CardLabel.new(slug: "ace-spec", name: "Ace Spec", family: "role", position: 10)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "a family outside the vocabulary is refused" do
    label = CardLabel.new(slug: "gust", name: "Gust", family: "mechanic", position: 10)

    assert_not label.valid?
    assert_includes label.errors[:family], "is not included in the list"
  end

  # The slug reaches a URL query and a DOM class, and it is what stage 2's rules will key on.
  test "a slug that is not lowercase-kebab is refused" do
    assert_not CardLabel.new(slug: "ACE SPEC", name: "x", family: "type", position: 1).valid?
  end

  test "the family scopes order by position then slug" do
    b = CardLabel.create!(slug: "b", name: "B", family: "type", position: 20)
    a = CardLabel.create!(slug: "a", name: "A", family: "type", position: 10)
    CardLabel.create!(slug: "c", name: "C", family: "role", position: 5)

    assert_equal [ a, b ], CardLabel.types.to_a
    assert_equal [ "c" ], CardLabel.roles.pluck(:slug)
  end

  # Without this, a typo'd token surfaced only inside CardLabels::ImportJob, after a full
  # round-trip through the admin form and the job queue — the form told the admin to watch the
  # imports table for a result that was never going to come.
  test "a source_query that is not a Limitless search token is refused" do
    label = CardLabel.new(slug: "gust", name: "Gust", family: "type", position: 10,
                          source_query: "not a token")

    assert_not label.valid?
    assert_includes label.errors[:source_query], "is not a valid Limitless search token"
  end

  test "a blank source_query is allowed" do
    label = CardLabel.new(slug: "gust", name: "Gust", family: "role", position: 10, source_query: "")

    assert label.valid?
  end

  test "a well-formed source_query is allowed" do
    label = CardLabel.new(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10,
                          source_query: "is:ace")

    assert label.valid?
  end

  test "destroying a label takes its assignments with it" do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    label.assignments.create!(fingerprint: "fp", source: "imported")

    assert_difference "CardLabelAssignment.count", -1 do
      label.destroy
    end
  end

  # ROLES is the vocabulary stage 2 keys its suggestion rules on, and every slug in it is written
  # into the database by the seed — so a slug the model would refuse is a role that silently never
  # exists. Underscores are the trap: `energy_acceleration` reads better in Ruby than
  # `energy-acceleration` and fails this format, which nothing else would report until a fresh
  # database came up short a role.
  test "every role in the vocabulary passes the model's own rules" do
    CardLabel::ROLES.each do |attributes|
      label = CardLabel.new(family: "role", **attributes)

      assert label.valid?, "#{attributes[:slug]}: #{label.errors.full_messages.to_sentence}"
    end
  end

  test "the role vocabulary repeats no slug, no name and no position" do
    assert_equal CardLabel::ROLES.size, CardLabel::ROLES.map { |role| role[:slug] }.uniq.size
    assert_equal CardLabel::ROLES.size, CardLabel::ROLES.map { |role| role[:name] }.uniq.size
    assert_equal CardLabel::ROLES.size, CardLabel::ROLES.map { |role| role[:position] }.uniq.size
  end

  # The description is user-facing: the curation screen prints it as a title and the report reads
  # it beside the section. A role with none is a checkbox nobody can interpret.
  test "every role says what it means" do
    CardLabel::ROLES.each do |role|
      assert role[:description].present?, "#{role[:slug]} carries no description"
    end
  end
end
