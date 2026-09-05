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

  test "destroying a label takes its assignments with it" do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    label.assignments.create!(fingerprint: "fp", source: "imported")

    assert_difference "CardLabelAssignment.count", -1 do
      label.destroy
    end
  end
end
