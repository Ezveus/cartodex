require "test_helper"

class TournamentEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @tournament = tournaments(:two) # user one has no entry here, so a fresh one is valid
  end

  test "requires a tournament, a user and a deck" do
    entry = TournamentEntry.new

    assert_not entry.valid?
    assert_includes entry.errors[:tournament], "must exist"
    assert_includes entry.errors[:user], "must exist"
    assert_includes entry.errors[:deck], "must exist"
  end

  test "rejects a placement greater than the participant count" do
    entry = build_entry(participant_count: 8, placement: 9)

    assert_not entry.valid?
    assert_includes entry.errors[:placement], "can't be greater than the number of participants"
  end

  test "rejects a deck belonging to another user" do
    entry = build_entry(deck: decks(:two))

    assert_not entry.valid?
    assert_includes entry.errors[:deck], "must belong to the same user"
  end

  test "rejects a tournament profile belonging to another user" do
    entry = build_entry(tournament_profile: tournament_profiles(:giovanni))

    assert_not entry.valid?
    assert_includes entry.errors[:tournament_profile], "must belong to the same user"
  end

  test "rejects a negative championship point total" do
    entry = build_entry(championship_points: -1)

    assert_not entry.valid?
    assert_includes entry.errors[:championship_points], "must be greater than or equal to 0"
  end

  # First branch of one_entry_per_player: the same profile twice in one event.
  test "refuses a second entry for the same tournament profile" do
    existing = tournament_entries(:one)
    duplicate = TournamentEntry.new(
      user: existing.user, tournament: existing.tournament,
      deck: existing.deck, tournament_profile: existing.tournament_profile
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:tournament], "already has a participation for this player"
  end

  # Second branch: no profile at all. This is the one a single unique index would have missed,
  # because SQLite treats NULLs as distinct.
  test "refuses a second profile-less entry for the same user and tournament" do
    existing = tournament_entries(:shared_event)
    assert_nil existing.tournament_profile_id, "sanity: this fixture is the profile-less case"

    duplicate = TournamentEntry.new(
      user: existing.user, tournament: existing.tournament, deck: existing.deck
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:tournament], "already has a participation for this player"
  end

  # The `user_id` half of the profile-less branch, which the refusal test above cannot pin:
  # `where(tournament_profile_id: nil)` renders as IS NULL, so the profile branch answers
  # correctly for a nil profile too, and a branch that dropped user_id would still refuse the
  # duplicate. What only the right branch allows is a *second member* with no profile.
  test "another member may record a profile-less entry on the same tournament" do
    existing = tournament_entries(:shared_event)
    assert_nil existing.tournament_profile_id, "sanity: this fixture is the profile-less case"

    other = TournamentEntry.new(
      user: users(:one), tournament: existing.tournament, deck: decks(:one)
    )

    assert other.valid?, other.errors.full_messages.to_sentence
  end

  test "allows one entry per profile the user manages" do
    existing = tournament_entries(:one)
    second = TournamentEntry.new(
      user: existing.user, tournament: existing.tournament,
      deck: existing.deck, tournament_profile: tournament_profiles(:misty)
    )

    assert second.valid?, second.errors.full_messages.to_sentence
  end

  test "two members may both have an entry in one tournament" do
    assert_equal 2, tournaments(:one).entries.count
    assert_equal 2, tournaments(:one).entries.map(&:user_id).uniq.size
  end

  test "an entry does not collide with itself when re-saved" do
    assert tournament_entries(:one).valid?
  end

  # DeckResult#entry_belongs_to_same_deck is the other half of this rule, and it is checked when
  # the *result* is saved — nothing re-checks it when the entry moves underneath. Left alone,
  # the update succeeds and every attached result silently becomes invalid.
  test "refuses to change deck while matches are attached to the entry" do
    entry = tournament_entries(:one)
    entry.deck.deck_results.create!(result: "win", played_at: Time.current, tournament_entry: entry)
    other_deck = Deck.create!(user: users(:one), name: "Other Deck", standard_pool: standard_pools(:twm_por))

    assert_not entry.update(deck: other_deck)
    assert_includes entry.errors[:deck], "can't be changed while matches are attached to this participation"
    assert_equal decks(:one).id, entry.reload.deck_id
  end

  test "the deck may be changed once no match is attached" do
    entry = tournament_entries(:one)
    assert_empty entry.deck_results, "sanity: the fixture entry has no attached match"

    other_deck = Deck.create!(user: users(:one), name: "Other Deck", standard_pool: standard_pools(:twm_por))

    assert entry.update(deck: other_deck), entry.errors.full_messages.to_sentence
  end

  test "suggested_championship_points reads the grid with the event's tier and its own placement" do
    entry = build_entry(placement: 1)
    entry.tournament = tournaments(:two) # league_cup

    assert_equal 50, entry.suggested_championship_points
  end

  test "suggested_championship_points is nil without a placement" do
    assert_nil build_entry(placement: nil).suggested_championship_points
  end

  test "standard_top_cut looks up the indicative band by participant count" do
    assert_nil build_entry(participant_count: 8).standard_top_cut
    assert_equal 4, build_entry(participant_count: 16).standard_top_cut
    assert_equal 8, build_entry(participant_count: 64).standard_top_cut
    assert_equal 16, build_entry(participant_count: 226).standard_top_cut
    assert_equal 32, build_entry(participant_count: 1024).standard_top_cut
    assert_equal 64, build_entry(participant_count: 2000).standard_top_cut
  end

  test "standard_top_cut is nil without a participant count" do
    assert_nil build_entry(participant_count: nil).standard_top_cut
  end

  test "destroying an entry leaves its matches and its event alone" do
    entry = tournament_entries(:one)
    result = entry.deck.deck_results.create!(result: "win", played_at: Time.current, tournament_entry: entry)

    assert_no_difference -> { Tournament.count } do
      assert_difference -> { DeckResult.count }, 0 do
        entry.destroy
      end
    end

    assert_nil result.reload.tournament_entry_id
  end

  # Already true before this feature, and worth pinning now that a deck can have no owner:
  # deck_belongs_to_user compares deck.user_id != user_id, so a field list can never be used as
  # a member's own participation deck. The guard was there for free — this is the test that says
  # somebody checked.
  test "a tournament field list cannot be used as a participation deck" do
    entry = tournament_entries(:one)

    refute entry.update(deck: decks(:field_list))
    assert_includes entry.errors[:deck], "must belong to the same user"
  end

  # :nullify, not :destroy — the opposite call from Tournament#standings, and the whole reason
  # the two tables are separate: deleting my private participation must not erase a public row
  # other members read.
  test "deleting a participation unlinks its standing rather than deleting it" do
    entry = tournament_entries(:one)
    standing = tournament_standings(:ash_masters)
    standing.update!(tournament_entry: entry)

    assert_no_difference -> { TournamentStanding.count } do
      entry.destroy
    end
    assert_nil standing.reload.tournament_entry_id
  end

  private

  def build_entry(attrs = {})
    TournamentEntry.new({ user: @user, tournament: @tournament, deck: @deck }.merge(attrs))
  end
end
