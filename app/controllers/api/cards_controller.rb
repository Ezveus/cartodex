module Api
  class CardsController < ApplicationController
    include CardSearchable

    RESULT_LIMIT = 20
    # How many printings of one card name may take those slots. Small on purpose:
    # a deck builder means one of the recent printings, and the older ones are
    # reached by naming the set ("boss's orders pal"), which the query parser
    # already understands. Without a cap a heavily reprinted card takes all 20 and
    # a differently named card is unreachable no matter what the user types.
    PRINTINGS_PER_NAME = 3

    # Newest set first, cards whose set is not imported last. `release_date IS
    # NULL` sorts 0 before 1, which is NULLS LAST spelled portably;
    # `CAST(set_number AS INTEGER)` keeps 9 ahead of 10 within a set. Same shape
    # as CardsController#index and Cards::Printings.
    #
    # Spelled twice because it is applied twice: once inside the subquery, where
    # the join is in scope, and once outside it, where the joined column survives
    # only under the alias the subquery gave it.
    RANK_ORDER  = "card_sets.release_date IS NULL, card_sets.release_date DESC, CAST(cards.set_number AS INTEGER)"
    FINAL_ORDER = "cards.set_release_date IS NULL, cards.set_release_date DESC, CAST(cards.set_number AS INTEGER)"

    before_action :authenticate_user!

    def index
      query = params[:q].to_s.strip
      cards = if query.length >= 2
        scope = apply_card_name_filter(Card.all, query)
        scope = scope.where(card_type: params[:type]) if params[:type].present?
        newest_printings_first(scope)
      else
        Card.none
      end
      render json: cards.map { |c| card_json(c) }
    end

    private

    # The 20 rows this endpoint returns used to be filtered down by the callers —
    # the archetype pickers asked only for Pokémon and then collapsed printings by
    # name — so neither the order nor the spread across names ever showed. Now
    # that a picker designates an exact printing, every printing of every matching
    # card competes for those slots, so the query has to decide both: which
    # printings of a name it keeps (the newest PRINTINGS_PER_NAME of it), and
    # which names reach the user.
    #
    # The rank is computed over the whole match rather than over a fetched
    # prefix, or the cards a very common word buries would still be lost.
    def newest_printings_first(scope)
      ranked = scope
        .left_joins(:card_set)
        .select(
          "cards.*",
          "card_sets.release_date AS set_release_date",
          Arel.sql("ROW_NUMBER() OVER (PARTITION BY cards.name_normalized ORDER BY #{RANK_ORDER}) AS printing_rank")
        )

      Card.from(ranked, :cards)
        .where(printing_rank: ..PRINTINGS_PER_NAME)
        .order(Arel.sql(FINAL_ORDER))
        .limit(RESULT_LIMIT)
    end

    def card_json(card)
      { id: card.id, name: card.name, card_type: card.card_type,
        set_name: card.set_name, set_number: card.set_number,
        image_url: card.image_url }
    end
  end
end
