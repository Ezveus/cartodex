# Anchors Standard decks and tournaments that predate the anchor column.
#
# A rake task rather than a migration: the pools it needs come from db/seed, which
# runs after db:migrate, so a migration would find an empty table. Idempotent, so
# it can be re-run after the seed is corrected.
class StandardPools::AnchorBackfill < ApplicationService
  Result = Struct.new(:decks, :tournaments, :skipped, keyword_init: true)

  def call
    skipped = []
    oldest = StandardPool.order(:legal_on).first
    current = StandardPool.current

    if oldest.nil?
      skipped << "no Standard pool exists yet — run bin/rails db:seed first"
      return Result.new(decks: 0, tournaments: 0, skipped: skipped)
    end

    # Every pool being future-dated does not trip the guard above — `oldest` is ordered by
    # legal_on and is a real row — but `current` is nil, and writing it would blank the
    # anchors while update_all still reported the rows it touched. A false success in the
    # one tool an operator trusts mid-migration, so it is reported instead.
    if current.nil?
      skipped << "no Standard pool has released yet — decks left unanchored"
      return Result.new(decks: 0, tournaments: backfill_tournaments(oldest), skipped: skipped)
    end

    Result.new(
      decks: backfill_decks(current), tournaments: backfill_tournaments(oldest), skipped: skipped
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

  # A tournament has a real date, so its answer is exact. An event older than the
  # whole seeded history falls back to the oldest pool: NULL would be unsavable on
  # its next edit.
  def backfill_tournaments(oldest)
    Tournament.where(format: "standard", standard_pool_id: nil).find_each.count do |tournament|
      pool = StandardPool.at(tournament.date) || oldest
      tournament.update_column(:standard_pool_id, pool.id)
    end
  end
end
