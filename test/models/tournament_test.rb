require "test_helper"

class TournamentTest < ActiveSupport::TestCase
  test "requires name and date" do
    tournament = Tournament.new
    assert_not tournament.valid?
    assert_includes tournament.errors[:name], "can't be blank"
    assert_includes tournament.errors[:date], "can't be blank"
  end

  test "requires other_format_name when format is other" do
    tournament = build_tournament(format: "other")
    assert_not tournament.valid?
    assert_includes tournament.errors[:other_format_name], "can't be blank"
  end

  test "clears other_format_name when format is not other" do
    tournament = build_tournament(format: "standard", standard_pool: standard_pools(:twm_por), other_format_name: "Pocket")
    tournament.valid?
    assert_nil tournament.other_format_name
  end

  test "requires a standard pool when the format is standard" do
    tournament = build_tournament(format: "standard", standard_pool: nil)

    assert_not tournament.valid?
    assert_includes tournament.errors[:standard_pool], "can't be blank"
  end

  test "clears the standard pool when the format is not standard" do
    tournament = build_tournament(format: "expanded", standard_pool: standard_pools(:twm_por))

    tournament.validate

    assert_nil tournament.standard_pool_id
  end

  # Distinct from the clearing test above: that one only checks the field gets nilled out, not
  # that the record ends up valid. An unconditional presence validation would clear the field and
  # still fail — this is what actually proves the "if: :standard?" guard is doing its job.
  test "does not require a standard pool when the format is not standard" do
    assert build_tournament(format: "expanded", standard_pool: nil).valid?
  end

  test "format_label names the standard pool the tournament was played under" do
    tournament = build_tournament(format: "standard", standard_pool: standard_pools(:twm_por))

    assert_equal "Standard (TWM-POR)", tournament.format_label
  end

  test "refuses a second event with the same name on the same date" do
    duplicate = build_tournament(name: tournaments(:one).name, date: tournaments(:one).date)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "is already catalogued for this date"
  end

  # The whole reason name_normalized exists: SQLite's LIKE and lower() fold ASCII A-Z only, so
  # a uniqueness check written against `name` would let this row through.
  test "the duplicate check folds case and accents" do
    tournaments(:one).update!(name: "Régionale de Lyon")

    duplicate = build_tournament(name: "RÉGIONALE DE LYON", date: tournaments(:one).date)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "is already catalogued for this date"
  end

  # (name_normalized, date) is the only thing between the catalog and two rows for one real
  # event, and a name arrives copy-pasted — with a trailing space, or a double space where a
  # line wrapped — far more often than it arrives typed.
  test "the duplicate check ignores surrounding and repeated whitespace" do
    duplicate = build_tournament(name: "  Regional   Championship ", date: tournaments(:one).date)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "is already catalogued for this date"
  end

  # (name_normalized, date) UNIQUE is a rule about the *public catalog* — two members must not
  # catalogue one real event twice — and it was never a claim about the world. Online event names
  # are arbitrary and repeat weekly, so the index is partial (WHERE online = 0) and the validation
  # is scoped to match it: a paper Regional and an online weekly may share a name and a date, and
  # neither is a duplicate of the other.
  test "an online event may share a name and a date with a catalogued one" do
    online = build_tournament(name: tournaments(:one).name, date: tournaments(:one).date, online: true)

    assert online.valid?
    assert_nothing_raised { online.save! }
  end

  test "two online events may share a name and a date" do
    date = Date.current
    Tournament.create!(name: "Pumpkaweekly #12", date: date, tier: "other", format: "expanded",
      online: true, external_key: "aaa")

    assert build_tournament(name: "Pumpkaweekly #12", date: date, online: true,
      external_key: "bbb").valid?
  end

  # What keeps one online event to one row instead. Partial, because SQLite treats NULLs as
  # distinct: over the whole column every paper event would collide with every other.
  test "two events may not share an external key" do
    date = Date.current
    Tournament.create!(name: "Pumpkaweekly #12", date: date, tier: "other", format: "expanded",
      online: true, external_key: "aaa")

    assert_raises ActiveRecord::RecordNotUnique do
      Tournament.create!(name: "Pumpkaweekly #13", date: date + 1, tier: "other", format: "expanded",
        online: true, external_key: "aaa")
    end
  end

  # The index behind the validation two tests above, and the reason to reach past the validation
  # to reach it: making that rule partial is exactly the edit that could have made it vacuous, and
  # a validation-only test would still pass with no index at all.
  test "the catalogue still refuses two rows for one paper event at the database" do
    duplicate = build_tournament(name: tournaments(:one).name, date: tournaments(:one).date)

    assert_raises ActiveRecord::RecordNotUnique do
      duplicate.save!(validate: false)
    end
  end

  test "the same name on another date is a different event" do
    assert build_tournament(name: tournaments(:one).name, date: tournaments(:one).date + 1).valid?
  end

  test "an event keeps its own name when re-saved" do
    assert tournaments(:one).valid?, "a persisted event must not collide with itself"
  end

  test "refuses to be destroyed while a participation points at it" do
    tournament = tournaments(:one)
    assert_predicate tournament.entries, :any?, "sanity: the fixture has participations"

    assert_no_difference -> { Tournament.count } do
      assert_not tournament.destroy
    end
  end

  test "is destroyed once nothing points at it" do
    tournament = tournaments(:one)
    tournament.entries.destroy_all

    assert_difference -> { Tournament.count }, -1 do
      assert tournament.destroy
    end
  end

  # Uppercase accented letter in the stored name on purpose — see the note in DeckTest: only
  # name_normalized can match a lowercase query against it.
  test "name_matching ignores case on accented letters" do
    tournament = tournaments(:one)
    tournament.update!(name: "RÉGIONALE de Lyon")

    %w[RÉGIONALE Régionale régionale].each do |query|
      assert_includes Tournament.name_matching(query), tournament, "#{query.inspect} must match"
    end
  end

  # The stored side and the query side share one normalization or they share none: squishing
  # only what is saved would make a name typed with a double space unfindable.
  test "name_matching squishes the query as well as the stored name" do
    tournament = tournaments(:one)
    tournament.update!(name: "Regional  Championship")

    [ "regional championship", "  regional   championship " ].each do |query|
      assert_includes Tournament.name_matching(query), tournament, "#{query.inspect} must match"
    end
  end

  test "name_matching treats LIKE metacharacters in the query as literals" do
    assert_includes Tournament.name_matching("regional"), tournaments(:one), "sanity: the plain spelling matches"
    assert_empty Tournament.name_matching("reg_onal"), "_ must not act as a wildcard"
    assert_empty Tournament.name_matching("regi%nal"), "% must not act as a wildcard"
  end

  test "every tournament fixture carries the normalization its name implies" do
    Tournament.find_each do |tournament|
      assert_equal tournament.name.squish.downcase, tournament.name_normalized,
        "#{tournament.name.inspect} fixture is out of step"
    end
  end

  test "participant_count_for reads the column for the division it is handed" do
    tournament = tournaments(:one)
    tournament.update!(junior_participant_count: 12, senior_participant_count: 30,
                       masters_participant_count: 512)

    assert_equal 12, tournament.participant_count_for("junior")
    assert_equal 30, tournament.participant_count_for(:senior)
    assert_equal 512, tournament.participant_count_for("masters")
    assert_nil tournament.participant_count_for("mystery")
  end

  test "a field size must be a positive integer when given" do
    tournament = tournaments(:one)

    refute tournament.update(masters_participant_count: 0)
    assert_includes tournament.errors.attribute_names, :masters_participant_count
    assert tournament.update(masters_participant_count: nil)
  end

  # :destroy, unlike :entries' restrict_with_error: a standing is a line of the event's own
  # public sheet, not somebody's private record of having been there.
  test "deleting an event takes its standings with it" do
    tournament = tournaments(:one)
    tournament.entries.destroy_all

    assert_difference -> { TournamentStanding.count }, -tournament.standings.count do
      assert tournament.destroy
    end
  end

  test "an event still refuses to be deleted while a participation survives" do
    tournament = tournaments(:one)

    assert_no_difference -> { TournamentStanding.count } do
      refute tournament.destroy
    end
  end

  private

  def build_tournament(attrs = {})
    Tournament.new({
      name: "Test Tournament",
      date: Date.current,
      tier: "regional",
      format: "expanded"
    }.merge(attrs))
  end
end
