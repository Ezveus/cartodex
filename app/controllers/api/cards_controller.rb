module Api
  class CardsController < ApplicationController
    include CardSearchable

    before_action :authenticate_user!

    def index
      query = params[:q].to_s.strip
      cards = if query.length >= 2
        scope = apply_card_name_filter(Card.all, query)
        scope = scope.where(card_type: params[:type]) if params[:type].present?
        newest_printings_first(scope).limit(20)
      else
        Card.none
      end
      render json: cards.map { |c| card_json(c) }
    end

    private

    # Newest set first, cards whose set is not imported last. The 20 rows this
    # endpoint returns used to be filtered down by the callers — the archetype
    # pickers asked only for Pokémon and then collapsed printings by name — so
    # the absence of an ORDER BY never showed. Now that a picker designates an
    # exact printing, every printing of every matching card competes for those
    # 20 slots, and rowid order would decide which ones the user never sees.
    #
    # `release_date IS NULL` sorts 0 before 1, which is NULLS LAST spelled
    # portably; `CAST(set_number AS INTEGER)` keeps 9 ahead of 10 within a set.
    # Same shape as CardsController#index and Cards::Printings.
    def newest_printings_first(scope)
      scope
        .left_joins(:card_set)
        .order(Arel.sql("card_sets.release_date IS NULL, card_sets.release_date DESC, CAST(cards.set_number AS INTEGER)"))
    end

    def card_json(card)
      { id: card.id, name: card.name, card_type: card.card_type,
        set_name: card.set_name, set_number: card.set_number,
        image_url: card.image_url }
    end
  end
end
