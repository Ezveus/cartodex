# Anchors Standard decks and tournaments that predate the anchor column.
#
# A rake task rather than a migration: the pools it needs come from db/seed, which
# runs after db:migrate, so a migration would find an empty table.
#
# Re-running is safe but not corrective. The scope filters on a NULL anchor, so a row
# this task already wrote is never revisited — including a tournament that got the
# oldest pool as a fallback because no pool covered its date. Seed the missing older
# pool, re-run, and that tournament keeps its guess, silently. So every fallback is
# named in `approximated`, which is the only chance an operator gets to fix it by hand.
class StandardPools::AnchorBackfill < ApplicationService
  Result = Struct.new(:decks, :tournaments, :skipped, :approximated, keyword_init: true)

  def call
    skipped = []
    oldest = StandardPool.order(:legal_on).first
    current = StandardPool.current

    if oldest.nil?
      skipped << "no Standard pool exists yet — run bin/rails db:seed first"
      return Result.new(decks: 0, tournaments: 0, skipped: skipped, approximated: [])
    end

    approximated = []

    # Every pool being future-dated does not trip the guard above — `oldest` is ordered by
    # legal_on and is a real row — but `current` is nil, and writing it would blank the
    # anchors while update_all still reported the rows it touched. A false success in the
    # one tool an operator trusts mid-migration, so it is reported instead.
    if current.nil?
      skipped << "no Standard pool has released yet — decks left unanchored"
      return Result.new(
        decks: 0, tournaments: backfill_tournaments(oldest, approximated),
        skipped: skipped, approximated: approximated
      )
    end

    Result.new(
      decks: backfill_decks(current), tournaments: backfill_tournaments(oldest, approximated),
      skipped: skipped, approximated: approximated
    )
  end

  private

  # created_at is not a build date — importing an old decklist today stamps today —
  # so every unanchored Standard deck takes the current pool. Visibly wrong for an
  # old deck beats plausibly wrong, and the deck form invites the user to correct it.
  def backfill_decks(current)
    Deck.where(format: "standard", standard_pool_id: nil)
        .update_all(standard_pool_id: current.id)
  end

  # A tournament has a real date, so its answer is exact — except for an event older than
  # the whole seeded history, which falls back to the oldest pool because NULL would be
  # unsavable on its next edit. That fallback is a guess, and since a re-run will never
  # revisit it, it is recorded by name rather than left to be discovered.
  def backfill_tournaments(oldest, approximated)
    Tournament.where(format: "standard", standard_pool_id: nil).find_each.count do |tournament|
      exact = StandardPool.at(tournament.date)
      approximated << "##{tournament.id} #{tournament.name} (#{tournament.date})" if exact.nil?
      tournament.update_column(:standard_pool_id, (exact || oldest).id)
    end
  end
end
