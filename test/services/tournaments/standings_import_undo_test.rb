require "test_helper"

class Tournaments::StandingsImportUndoTest < ActiveSupport::TestCase
  setup do
    @admin = users(:one)
    @tournament = tournaments(:one)
  end

  # The whole reason the receipt column exists: a bulk run writes rows into a public sheet, and
  # nothing else in the app can take them back out. There is no admin tournaments controller, and
  # a standing is otherwise only deletable one row at a time from the event page.
  test "destroys the unclaimed standings the run created" do
    first = create_standing("Brock")
    second = create_standing("Misty")
    import = create_import(created_standing_ids: [ first.id, second.id ])

    result = Tournaments::StandingsImportUndo.call(import)

    assert_equal 2, result.destroyed
    assert_equal 0, result.kept_claimed
    assert_not TournamentStanding.exists?(first.id)
    assert_not TournamentStanding.exists?(second.id)
  end

  # A claimed row is no longer only the run's: a member pressed "This is me" and adopted it as
  # their own published record. Deleting it because an admin mis-ran an import would erase
  # somebody else's work, so it survives — and is counted, because an admin who is told "Undid 2
  # standings" and finds three still on the sheet has been told the wrong thing.
  test "keeps a claimed standing and reports it" do
    claimed = create_standing("Brock", tournament_entry: tournament_entries(:one))
    unclaimed = create_standing("Misty")
    import = create_import(created_standing_ids: [ claimed.id, unclaimed.id ])

    result = Tournaments::StandingsImportUndo.call(import)

    assert_equal 1, result.destroyed
    assert_equal 1, result.kept_claimed
    assert TournamentStanding.exists?(claimed.id), "a claimed standing belongs to the member who claimed it"
    assert_not TournamentStanding.exists?(unclaimed.id)
  end

  # The button is reachable from the imports table forever, so it will be pressed twice. Striking
  # the destroyed ids off the receipt is what makes the second press destroy nothing rather than
  # re-reporting a count of rows that are already gone.
  test "a second undo destroys nothing" do
    standing = create_standing("Brock")
    import = create_import(created_standing_ids: [ standing.id ])

    Tournaments::StandingsImportUndo.call(import)
    second = Tournaments::StandingsImportUndo.call(import)

    assert_equal 0, second.destroyed
    assert_equal 0, second.kept_claimed
    assert_empty import.reload.created_standing_ids
  end

  # The mirror of the rule above: a claimed row's id stays on the receipt, because the claim may
  # later be severed with "Unlink" and an undo run after that should still be able to finish the
  # job. Keeping it is only safe because it destroys nothing on its own — see the no-op test.
  test "a claimed standing keeps its place on the receipt" do
    claimed = create_standing("Brock", tournament_entry: tournament_entries(:one))
    import = create_import(created_standing_ids: [ claimed.id ])

    Tournaments::StandingsImportUndo.call(import)

    assert_equal [ claimed.id ], import.reload.created_standing_ids
  end

  # An imported field list is an ownerless deck: it is publicly listed on /decks/shared and is
  # reachable for deletion through TournamentStanding#destroy_ownerless_deck and nowhere else. So
  # undoing the standing has to take it, or a bad run leaves public decks nobody can remove — and
  # it must happen through that existing callback rather than through a deck delete written here,
  # which is the guard that keeps a member's own deck out of reach.
  test "an imported field list goes with the standing that owned it" do
    list = Deck.create!(name: "Brock — Regional Championship (2026-03-14)", format: "glc", shared: true)
    standing = create_standing("Brock", deck: list)
    import = create_import(created_standing_ids: [ standing.id ])

    Tournaments::StandingsImportUndo.call(import)

    assert_not Deck.exists?(list.id)
  end

  # Events created by a run are left standing on purpose. An empty catalog entry is harmless,
  # while one another member has since attached a participation or a hand-typed row to is not this
  # button's to delete — and `Tournament has_many :entries, dependent: :restrict_with_error` would
  # refuse anyway, turning a partial undo into an exception.
  test "leaves the tournament alone" do
    standing = create_standing("Brock")
    import = create_import(created_standing_ids: [ standing.id ])

    Tournaments::StandingsImportUndo.call(import)

    assert Tournament.exists?(@tournament.id)
  end

  # Standings are wiki-governed: the sheet an import wrote into also holds rows members typed by
  # hand, and rows from earlier runs. Undo is scoped to its own receipt and to nothing else, or
  # one bad import would take the whole event's sheet with it.
  test "leaves standings the run did not create alone" do
    mine = create_standing("Brock")
    import = create_import(created_standing_ids: [ mine.id ])

    Tournaments::StandingsImportUndo.call(import)

    assert TournamentStanding.exists?(tournament_standings(:ash_masters).id)
    assert TournamentStanding.exists?(tournament_standings(:giovanni_masters).id)
  end

  # Any member may delete any standing, so a recorded id may name a row that is already gone by
  # the time undo runs. That is an ordinary lookup miss and not a failure: the row is in the state
  # the button was pressed to reach.
  test "a standing already deleted by hand is not an error" do
    standing = create_standing("Brock")
    import = create_import(created_standing_ids: [ standing.id ])
    standing.destroy!

    result = Tournaments::StandingsImportUndo.call(import)

    assert_equal 0, result.destroyed
    assert_equal 0, result.kept_claimed
  end

  # No other kind of import records what it created, so an undo of one has nothing to act on.
  # Raising rather than quietly returning zeroes: a caller that reached here with a deck import
  # has a bug, and answering "Undid 0 standings." would hide it.
  test "refuses an import of any other kind" do
    import = @admin.imports.create!(kind: "deck", label: "Raging Bolt", status: "completed")

    error = assert_raises(ArgumentError) { Tournaments::StandingsImportUndo.call(import) }
    assert_match(/limitless_standings/, error.message)
  end

  # An enrich-only run used to be unundoable in both directions at once: the receipt was empty, so
  # this button did nothing, and Tournaments::StandingsController#standing_params does not permit
  # deck_id, so the member whose row it was could not detach the list either — their only way out
  # was destroying their own public standing.
  test "takes an imported field list back off a row it did not create" do
    standing = tournament_standings(:ash_masters)
    deck = Deck.create!(user: nil, name: "Ash Ketchum — field list", shared: true,
      standard_pool: StandardPool.current)
    standing.update!(deck: deck)
    import = users(:one).imports.create!(
      kind: "limitless_standings", label: "Raging Bolt — Limitless deck 280", status: "completed",
      enriched_standing_ids: [ standing.id ]
    )

    result = Tournaments::StandingsImportUndo.call(import)

    assert_equal 1, result.detached
    assert_equal 0, result.destroyed
    # The member's row stays; only the list the run attached to it goes.
    assert TournamentStanding.exists?(standing.id)
    assert_nil standing.reload.deck_id
    assert_not Deck.exists?(deck.id)
    assert_empty import.reload.enriched_standing_ids
  end

  private

  # archetypes(:standings_marker) and no other fixture — TournamentStanding's cascade off
  # Archetype is restrict_with_error, so standings need an archetype nothing else in the suite
  # destroys or builds decks from. See the note in test/fixtures/archetypes.yml.
  def create_standing(player_name, **attributes)
    @tournament.standings.create!(
      player_name: player_name,
      division: "masters",
      archetype: archetypes(:standings_marker),
      created_by: @admin,
      **attributes
    )
  end

  def create_import(created_standing_ids:)
    @admin.imports.create!(
      kind: "limitless_standings",
      label: "Raging Bolt (deck 280)",
      status: "completed",
      created_standing_ids: created_standing_ids
    )
  end
end
