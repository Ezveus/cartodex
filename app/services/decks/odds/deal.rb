module Decks
  module Odds
    # The probability model of one game of Pokémon TCG, and nothing else: it knows a deck size, how
    # many of those cards are Basic Pokémon, how big a hand is and how many prizes are dealt. It
    # never sees a Deck, a Card or the database — which is what lets deal_test.rb check every
    # formula against exhaustive enumeration of an 8-card deck rather than against fixtures, and it
    # is the reason this file is separate from Decks::Odds::Report at all: it carries all of the
    # mathematical risk of the feature.
    #
    # One assumption carries everything below: the deck is a uniform random permutation of its N
    # cards, and the deal reads positions off it.
    #
    #   position   1 … h        h+1 … h+prize_count       h+prize_count+1 …
    #              hand         prizes                    draw pile, in order
    #
    # Three consequences, and each makes a section of the page computable:
    #
    #   1. "Accessible after d draws" is a *fixed* set of positions, so the cards there form a
    #      uniform subset of the deck and accessibility is a plain hypergeometric question. No
    #      simulation, no recursion over turns.
    #   2. A prize is not permanently lost — taking p prizes adds a uniform p-subset of the prize
    #      block. That subset is random but independent of the permutation, so `d` and `p` enter
    #      every formula the same way, through their sum. They keep separate controls because their
    #      *ceilings* differ, not because the mathematics distinguishes them.
    #   3. The mulligan conditions the hand and nothing else. A hand with no Basic Pokémon is never
    #      kept, so the hand is a uniform h-subset conditioned on containing at least one Basic;
    #      the positions after it are untouched by that condition.
    #
    # See docs/architecture/deck-odds.md and
    # docs/superpowers/specs/2026-09-12-deck-odds-design.md § The model.
    class Deal
      HAND_SIZE = 7
      PRIZE_COUNT = 6

      # Raised rather than answered with nil. Every caller has to have decided that the deck can
      # start a game before it asks for a probability, and a nil silently formatted as "0.00 %" is
      # exactly the failure this exists to make loud.
      Unplayable = Class.new(StandardError)

      attr_reader :deck_size, :basics, :hand_size, :prize_count

      def initialize(deck_size:, basics:, hand_size: HAND_SIZE, prize_count: PRIZE_COUNT)
        @deck_size = deck_size
        @basics = basics
        @hand_size = hand_size
        @prize_count = prize_count
        @binomials = {}
      end

      # A hand can be dealt, and at least one deal of it is keepable. Both halves are reachable from
      # the page: a deck under construction holds three cards, and a deck of 60 Trainers holds no
      # Basic Pokémon. Decks::Odds::Report passes prize_count: 0 below 13 cards, so the first half
      # reads `deck_size >= 7` there.
      def playable?
        deck_size >= hand_size + prize_count && basics.positive?
      end

      def mulligan_rate
        guard!

        @mulligan_rate ||= ratio(binomial(deck_size - basics, hand_size), binomial(deck_size, hand_size))
      end

      # The expected number of mulligans before a keepable hand. Each redeal is independent, so the
      # count is geometric: the sum of n * m^n * (1 - m) is m / (1 - m).
      def mean_mulligans
        mulligan_rate / (1 - mulligan_rate)
      end

      def keepable
        1 - mulligan_rate
      end

      # P(at least one copy from every bucket is accessible | the hand was keepable).
      #
      # `buckets` is [[copies, non_basic_copies], …] and the buckets must be disjoint — which is
      # what lets the size of a union be a sum rather than a set computation, and is why
      # Decks::Odds::Combo enforces disjointness client-side *and* on the server. Inclusion-exclusion
      # over the subsets S of the buckets, at most 2^4 = 16 terms.
      def all_buckets(buckets:, seen:)
        guard!

        count = buckets.size
        total = (0..count).sum do |size|
          sign = size.even? ? 1 : -1

          (0...count).to_a.combination(size).sum do |subset|
            copies = subset.sum { |index| buckets[index][0] }
            non_basic_copies = subset.sum { |index| buckets[index][1] }

            sign * (inaccessible(copies, seen) - inaccessible_and_no_basic(copies, non_basic_copies, seen))
          end
        end

        total / keepable
      end

      # The one-bucket case of the above, which is every row of the per-card table and every role
      # row. Written as a delegation rather than as its own formula on purpose: a projection that
      # disagreed with the combination calculator would warn the reader about the wrong thing.
      def accessible(copies:, non_basic_copies:, seen:)
        all_buckets(buckets: [ [ copies, non_basic_copies ] ], seen: seen)
      end

      # The prize questions are deliberately *not* conditioned on the mulligan, and the reason once
      # written here was wrong. "The mulligan condition touches the hand alone" is true of the
      # positions and false of the probability: the hand and the prize block are dealt from one
      # deck, so they are dependent, and conditioning on a keepable hand does move these numbers.
      # Measured against the same exhaustive enumeration deal_test.rb uses, on a 60-card deck: a
      # 1-of Basic is printed at 10.0000 % where the conditional answer is 9.6889 %, a 4-of Basic
      # 0.0031 % against 0.0026 %, and a 1-of Trainer 10.0000 % against 10.0778 % — the sign follows
      # the card type, because knowing the hand held a Basic makes the rest of the deck slightly
      # poorer in Basics and slightly richer in everything else.
      #
      # It stays unconditional on purpose. "Where are my copies" is a question about the deal that
      # happened, not about the deals that were thrown away, and a player looking at a prize map is
      # not asking a conditional question. What is *not* optional is saying so: Decks::Odds::MethodNote
      # carries it as a stated limit, because two measures under one page is exactly the kind of
      # thing a reader would otherwise take for one.
      def at_least_one_prized(copies:)
        return Rational(0) if prize_count.zero?

        1 - ratio(binomial(deck_size - copies, prize_count), binomial(deck_size, prize_count))
      end

      # Every copy prized *and* none of them among the `taken` prizes already collected — which is
      # what "still unreachable" means, and why this curve is indexed by prizes taken alone rather
      # than by the `seen` total every other cell uses.
      def all_prized(copies:, taken: 0)
        return Rational(0) if prize_count.zero? || copies > prize_count

        ratio(binomial(prize_count, copies), binomial(deck_size, copies)) *
          ratio(binomial(prize_count - copies, taken), binomial(prize_count, taken))
      end

      # The widest `seen` the page can ask for: every card outside the hand. Also the length of every
      # curve Decks::Odds::Report precomputes, which is 54 points on a 60-card deck.
      def max_seen = deck_size - hand_size

      # …and the widest `d` on its own, the prize block being reached through `p` instead.
      def max_draws = deck_size - hand_size - prize_count

      private

      def guard!
        return if playable?

        raise Unplayable, "a #{deck_size}-card deck with #{basics} Basic Pokémon cannot start a game"
      end

      # P(no copy of the target is in the hand, and none among the first `seen` cards outside it).
      # Two factors: the hand, and the rest. Given a hand holding none of them, the remaining
      # deck_size - hand_size cards still hold all `copies`, and the `seen` accessible positions
      # among those must avoid them too.
      def inaccessible(copies, seen)
        ratio(binomial(deck_size - copies, hand_size), binomial(deck_size, hand_size)) *
          rest_factor(copies, seen)
      end

      # The same, and the hand holds no Basic Pokémon either. `non_basic_copies` is the only place
      # the overlap between the target and the Basics appears: a target copy that *is* a Basic is
      # already excluded by `basics`, and adding it twice is the single most likely way to get this
      # file wrong. The mixed case in deal_test.rb is what catches it.
      def inaccessible_and_no_basic(copies, non_basic_copies, seen)
        ratio(binomial(deck_size - basics - non_basic_copies, hand_size), binomial(deck_size, hand_size)) *
          rest_factor(copies, seen)
      end

      def rest_factor(copies, seen)
        ratio(binomial(deck_size - hand_size - copies, seen), binomial(deck_size - hand_size, seen))
      end

      # Belt on top of the callers' clamps: an out-of-range `seen` or `taken` makes a denominator
      # zero, and answering 0 there is both correct (you cannot avoid what you have already seen all
      # of) and better than a ZeroDivisionError reaching a page.
      def ratio(numerator, denominator)
        denominator.zero? ? Rational(0) : Rational(numerator, denominator)
      end

      # Memoised for the life of one Deal, which is the life of one deck's report: that report asks
      # for roughly 1 350 evaluations over one (N, b) pair, and the hand-side binomials are the same
      # every time. Measured on 2 000 evaluations: 20.1 ms unmemoised, 7.6 ms memoised.
      def binomial(n, k)
        return 0 if k.negative? || n.negative? || k > n

        @binomials[[ n, k ]] ||= (0...k).reduce(1) { |product, i| product * (n - i) / (i + 1) }
      end
    end
  end
end
