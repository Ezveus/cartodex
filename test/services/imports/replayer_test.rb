require "test_helper"

class Imports::ReplayerTest < ActiveJob::TestCase
  # Every row belongs to users(:two), never to the admin who would click: the replay runs as the
  # import's own user, and a row owned by the clicker could not tell the two apart.
  setup do
    @owner = users(:two)
  end

  # --- what each kind enqueues -------------------------------------------------------------------

  # The decklist differs from the label on purpose: Retry re-ran the label — the deck's *name* — as
  # its decklist, and only an args assertion with two different strings can see that again.
  test "a deck import replays its decklist and its name, as its owner" do
    import = imported("deck", "Raging Bolt", { "decklist" => "4 Honedge POR 56", "name" => "Raging Bolt" })

    replay = Imports::Replayer.call(import)

    assert_enqueued_with(job: Decks::ImportJob, args: [ "4 Honedge POR 56", @owner, "Raging Bolt", replay ])
  end

  # The stored URL is not the one the label rebuilds, on purpose: Retry rebuilt it from the label,
  # and with the two equal a replay doing that again would pass.
  test "a card set import replays its stored URL, not one rebuilt from the label" do
    import = imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG?display=list" })

    replay = Imports::Replayer.call(import)

    assert_enqueued_with(job: CardSets::ImportJob,
      args: [ "https://limitlesstcg.com/cards/MEG?display=list", @owner, replay ])
  end

  test "a field-list import replays its standing and decklist, and stays on its event" do
    standing = tournament_standings(:ash_masters)
    import = imported("standing_list", "Ash — Event", { "standing_id" => standing.id, "decklist" => "4 Doublade TWM 62" },
      tournament: standing.tournament)

    replay = Imports::Replayer.call(import)

    assert_enqueued_with(job: Tournaments::StandingListImportJob,
      args: [ standing.id, "4 Doublade TWM 62", @owner.id, replay.id ])
    assert_equal standing.tournament, replay.tournament
  end

  test "a bulk standings import replays its options verbatim" do
    options = { "deck_id" => "280", "archetype_id" => 7, "event_filters" => [ "NAIC" ], "limit_per_event" => 4 }
    import = imported("limitless_standings", "Raging Bolt — Limitless deck 280", options)

    replay = Imports::Replayer.call(import)

    assert_enqueued_with(job: Tournaments::LimitlessImportJob, args: [ replay.id, @owner.id, options ])
  end

  test "a card-label import replays its label id" do
    import = imported("card_labels", "ACE SPEC (is:ace)", { "card_label_id" => 42 })

    replay = Imports::Replayer.call(import)

    assert_enqueued_with(job: CardLabels::ImportJob, args: [ replay.id, 42, @owner.id ])
  end

  # The job runs the token the label carries at replay time, so the new row has to name that one:
  # copied verbatim, the table and the job's flash would name a search that was never run.
  test "a card-label replay is labelled with the search it will actually run" do
    card_label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10,
                                   source_query: "is:tool")
    import = imported("card_labels", "ACE SPEC (is:ace)", { "card_label_id" => card_label.id })

    assert_equal "ACE SPEC (is:tool)", Imports::Replayer.call(import).label
  end

  # --- the new row and the old one ---------------------------------------------------------------

  # The original keeps its status, its error and its receipt: a bulk run's Undo reads that receipt
  # and nothing else can find the rows it wrote again.
  test "the replay is a new pending row and the original is left exactly as it was" do
    import = imported("limitless_standings", "Run", { "deck_id" => "280", "archetype_id" => 7 },
      status: "failed", error_message: "x", created_standing_ids: [ 1, 2 ])

    replay = assert_difference -> { Import.count }, 1 do
      Imports::Replayer.call(import)
    end

    import.reload
    assert_equal [ "failed", "x", [ 1, 2 ] ], [ import.status, import.error_message, import.created_standing_ids ]
    assert_equal [ "pending", nil, [] ], [ replay.status, replay.error_message, replay.created_standing_ids ]
    assert_equal [ import.kind, import.label, import.replay_params, @owner ],
      [ replay.kind, replay.label, replay.replay_params, replay.user ]
  end

  # A completed run is the main case — re-reading a set, picking up an archetype's new lists.
  test "a completed import is replayed" do
    import = imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, status: "completed")

    assert_enqueued_jobs 1 do
      Imports::Replayer.call(import)
    end
  end

  # --- refusals: nothing written, nothing enqueued ------------------------------------------------

  test "a bulk card add is refused in its own words" do
    import = imported("bulk_cards", "Collection — 5 copies", {}, status: "completed")

    error = assert_refused(import)

    assert_match(/adds copies rather than setting them/, error.message)
    assert_no_match(/before its parameters were stored/, error.message)
  end

  test "a row written before parameters were stored is refused" do
    import = imported("deck", "Raging Bolt", {})

    error = assert_refused(import)

    assert_match(/run before its parameters were stored/, error.message)
  end

  # The guard Admin::CardSetsController#import applies, minus the replayed row itself, and across
  # users: two runs of one set race whoever started them.
  test "a set already being imported by anybody refuses the replay" do
    imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, user: users(:one), status: "pending")
    import = imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, status: "failed")

    error = assert_refused(import)

    assert_equal "Set MEG is already being imported.", error.message
  end

  # The guard reads the other rows whatever the replayed row's own status: a pending row is refused
  # too when a second run of its set is already queued.
  test "a pending set import is refused while another run of that set is pending" do
    imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, status: "pending")
    import = imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, status: "pending")

    error = assert_refused(import)

    assert_equal "Set MEG is already being imported.", error.message
  end

  test "a stuck pending set import may replay itself" do
    import = imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, status: "pending")

    assert_enqueued_jobs 1 do
      Imports::Replayer.call(import)
    end
  end

  # The completed MEG row is what holds `.pending` in the guard: without it, a set imported twice
  # could never be reimported again, and nothing else here would notice.
  test "the set guard reads only pending card-set imports of the same set" do
    imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, status: "completed")
    imported("card_set", "TWM", { "url" => "https://limitlesstcg.com/cards/TWM" }, status: "pending")
    imported("deck", "MEG", { "decklist" => "x", "name" => "MEG" }, status: "pending")
    import = imported("card_set", "MEG", { "url" => "https://limitlesstcg.com/cards/MEG" }, status: "failed")

    assert_enqueued_jobs 1 do
      Imports::Replayer.call(import)
    end
  end

  # A kind admitted to REPLAYABLE_KINDS with no branch must fail before the row exists — otherwise
  # it leaves a pending import no job will ever finish. bulk_cards stands in for that kind: it has
  # no branch, and skipping the refusals is what reaching the dispatch takes.
  test "a kind with no replay written raises with nothing written" do
    import = imported("bulk_cards", "Collection", { "x" => 1 }, status: "completed")
    replayer = Imports::Replayer.new(import)
    replayer.define_singleton_method(:refuse!) { nil }

    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs do
        assert_raises(ArgumentError) { replayer.call }
      end
    end
  end

  private

  def imported(kind, label, params, user: @owner, **attrs)
    user.imports.create!(kind: kind, label: label, replay_params: params, **attrs)
  end

  def assert_refused(import)
    error = nil
    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs do
        error = assert_raises(Imports::Replayer::Refused) { Imports::Replayer.call(import) }
      end
    end
    error
  end
end
