module Decks
  module Odds
    # "What are the odds I see at least one of each of these, by then?" — the one control on
    # /decks/:id/odds that goes to the server.
    #
    # Its whole input is a string in the query, so every shape that is not a well-formed, disjoint
    # assignment of this deck's own groups fails closed into a sentence. The picker greys out a card
    # already used elsewhere, and that is a convenience, not a guarantee: disjointness is what lets
    # Deal#all_buckets add bucket sizes rather than compute a set union, so a param that broke it
    # would not raise — it would produce a *wrong number*, which is worse.
    #
    # The separators are "." between cards and "|" between buckets, neither of which can appear in a
    # group key: a key is 16 hex characters, or "card:<id>".
    class Combo < ApplicationService
      # At most 2^4 = 16 inclusion-exclusion terms, and more than four named cards stops being a
      # question anybody is asking.
      MAX_BUCKETS = 4
      BUCKET_SEPARATOR = "|"
      CARD_SEPARATOR = "."

      Result = Struct.new(:buckets, :curve, :error, keyword_init: true) do
        def asked? = buckets.any? || error.present?
        def answered? = curve.present?
      end

      def initialize(report:, param:)
        @report = report
        # to_s first: `?combo[a]=b` hands over ActionController::Parameters and `?combo[]=1` an
        # Array, neither of which answers to `split`. This action is publicly reachable and
        # PubliclyReachable rescues RecordNotFound and NotAuthorizedError and nothing else, so an
        # unguarded NoMethodError here is a 500 for any bot that tries the shape.
        @param = param.to_s
      end

      def call
        return blank if @param.strip.empty?
        return refuse("This deck cannot start a game, so there is nothing to compute.") unless @report.playable?

        groups = @param.split(BUCKET_SEPARATOR, -1)
        return refuse("Pick at most #{MAX_BUCKETS} groups of cards.") if groups.size > MAX_BUCKETS

        keys = groups.map { |group| group.split(CARD_SEPARATOR, -1).map(&:strip).reject(&:empty?) }
        return refuse("Every group must hold at least one card.") if keys.any?(&:empty?)

        flat = keys.flatten
        return refuse("A card can only be in one group.") if flat.uniq.size != flat.size

        entries = keys.map { |group| group.map { |key| @report.entries_by_key[key] } }
        return refuse("That combination names a card this deck does not play.") if entries.flatten.any?(&:nil?)

        Result.new(buckets: entries, curve: curve_for(entries), error: nil)
      end

      private

      def blank = Result.new(buckets: [], curve: nil, error: nil)

      # The buckets are dropped on refusal rather than echoed back: a half-parsed assignment rendered
      # beside its own error reads as though the page accepted part of it.
      def refuse(message) = Result.new(buckets: [], curve: nil, error: message)

      # Sizes add because the buckets are disjoint, which the checks above are what guarantee.
      def curve_for(entries)
        buckets = entries.map do |bucket|
          [ bucket.sum(&:copies), bucket.sum(&:non_basic_copies) ]
        end

        (0..@report.max_seen).map do |seen|
          Report.percent(@report.deal.all_buckets(buckets: buckets, seen: seen))
        end
      end
    end
  end
end
