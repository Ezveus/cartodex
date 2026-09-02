module Search
  # One text query, three groups of matches: the user's decks, the whole card catalog, and the
  # user's tournaments. Read-only, so no serialized_transaction.
  class Global < ApplicationService
    # CardSearchable lives under app/controllers/concerns but is a plain module with no controller
    # dependency. Including it here is deliberate: cards must match exactly as they do on the
    # cards page (set code and number included), so the "see all N cards" count is the count that
    # page will show.
    include CardSearchable

    MIN_QUERY_LENGTH = 2
    DEFAULT_LIMIT = 5

    Result = Data.define(
      :query, :decks, :deck_total, :cards, :card_total, :tournaments, :tournament_total,
      :shared_decks, :shared_deck_total
    ) do
      # True when the query was too short to run — the caller renders nothing at all, as opposed
      # to "searched and found nothing".
      def blank?
        query.length < Global::MIN_QUERY_LENGTH
      end

      def any?
        total.positive?
      end

      def total
        deck_total + card_total + tournament_total + shared_deck_total
      end
    end

    def initialize(user:, query:, limit: DEFAULT_LIMIT)
      @user = user
      @query = query.to_s.strip
      @limit = limit
    end

    def call
      return empty_result if @query.length < MIN_QUERY_LENGTH

      # standard_pool's bounds ride along because a result row renders the deck's
      # format badge, which names the pool from both of them — three extra queries per
      # Standard deck, on every keystroke, without this.
      decks = deck_scope.order(:name).limit(@limit)
        .includes(:archetype, standard_pool: [ :first_card_set, :last_card_set ]).to_a
      cards = card_scope.order(:name, :set_name).limit(@limit).to_a
      tournaments = tournament_scope.order(date: :desc).limit(@limit).to_a
      shared_decks = shared_deck_scope.order(:name).limit(@limit)
        .includes(:archetype, standard_pool: [ :first_card_set, :last_card_set ]).to_a

      Result.new(
        query: @query,
        decks: decks,
        deck_total: total_for(deck_scope, decks),
        cards: cards,
        card_total: total_for(card_scope, cards),
        tournaments: tournaments,
        tournament_total: total_for(tournament_scope, tournaments),
        shared_decks: shared_decks,
        shared_deck_total: total_for(shared_deck_scope, shared_decks)
      )
    end

    private

    # A page that came back short of the cap *is* the whole result set, so its size is the total.
    # Worth the branch: the card count is a second `LIKE '%…%'` scan of the entire catalog, run
    # on every keystroke, and only the queries broad enough to fill the page now pay for it.
    def total_for(scope, page)
      page.size < @limit ? page.size : scope.count
    end

    # Below the minimum, nothing touches the database — this is what keeps a one-letter query
    # cheap.
    def empty_result
      Result.new(
        query: @query, decks: [], deck_total: 0, cards: [], card_total: 0,
        tournaments: [], tournament_total: 0, shared_decks: [], shared_deck_total: 0
      )
    end

    # `search` is applied before any `includes`: it uses #or, which refuses to merge relations
    # that don't carry the same includes.
    #
    # A nil user is a visitor: nothing personal is searched, and nothing personal is queried
    # either — Deck.none and Tournament.none never touch the database.
    def deck_scope
      @deck_scope ||= @user ? @user.decks.search(@query) : Deck.none
    end

    def card_scope
      @card_scope ||= apply_card_name_filter(Card.all, @query)
    end

    def tournament_scope
      @tournament_scope ||= @user ? @user.tournaments.name_matching(@query) : Tournament.none
    end

    # Excluding the searcher's own decks is what keeps one deck out of two groups of the same
    # result list — and Search::ResultsList derives its option ids from the deck, so a
    # duplicate would emit one DOM id twice.
    def shared_deck_scope
      @shared_deck_scope ||= begin
        scope = Deck.shared
        scope = scope.where.not(user: @user) if @user
        scope.search(@query)
      end
    end
  end
end
