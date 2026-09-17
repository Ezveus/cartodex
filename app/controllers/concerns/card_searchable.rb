module CardSearchable
  extend ActiveSupport::Concern

  # The shape a token must have before the database is asked whether it names a set — the cheap
  # left operand of the `&&` in `card_set_code?` below, and a constant because the comment above
  # `global_test.rb`'s length-bound test quotes it back, so widening the bound without moving that
  # comment turns the quotation red. That one copy is bound and no other: this comment and
  # CLAUDE.md's paragraph on the same rule stay a reader's responsibility.
  #
  # Digits are admissible, and not merely tolerated: `30C` and `30CC` — 30th Celebration and its
  # Classic Collection — are the first two codes in the catalogue to carry one, and under a
  # letters-only shape their 184 printings could not be reached by a set-and-number query at all.
  # A *purely* numeric token is admissible for the same reason and costs nothing today, since
  # `Card.in_set_code(token).exists?` refuses every one of them; issue #111 is what makes it live,
  # SV2a being called "151" in Japanese. `Tournaments::OnlineResults::SET_RE` is spelled the same
  # way but for case, reading an already-uppercased source.
  #
  # The probe this admits follows `tokens.last` and not a position — "charizard v2" pays it where
  # "greninja 10" does not — and the number pop being greedy on the last token means a purely
  # numeric code, once one exists, is only ever readable penultimate: "Charizard 151" stays a card
  # named Charizard numbered 151.
  SET_CODE_SHAPE = /\A[a-zA-Z0-9]{2,5}\z/

  private

  def apply_card_name_filter(scope, query)
    tokens = query.split(/\s+/)
    # Both guards refuse to consume the *only* token, or a query that is just a name stops being
    # one: "56" would answer with every card numbered 56 in every set, and "asc" with all of ASC.
    # `|| number` is the exception the whole set-and-number lookup rides on — once a number has
    # been popped, "POR 56" is a printing and not a name, so the code may take the last token.
    # That exception is also what couples the two guards: `|| number` lets the code guard reach
    # `tokens.last` on an array the number pop may have emptied, so `tokens.length > 1` on the
    # line above is what keeps a token there. Relax it and "56" is not a wider answer but a
    # NoMethodError on nil.
    #
    # Where the two readings collide the set wins, and that is a deliberate loss: 12 of the 30
    # imported set codes are also substrings of card names, so "Mew 25" now answers with MEW 25
    # rather than with a card named Mew. "MEG 113" is how a player writes a printing; "name
    # contains this 2-5 character fragment *and* carries this number" is a coincidence filter nobody
    # types on purpose. Returning the union of both readings was weighed and refused — it keeps a
    # query answering three cards where the reader asked for one. Measured on the production
    # catalogue: 439 two-token queries answer something today, 224 of them go empty and 179 name
    # a different card.
    number = tokens.pop if tokens.length > 1 && tokens.last.match?(/\A\d+\z/)
    code   = tokens.pop if (tokens.length > 1 || number) && card_set_code?(tokens.last)
    name   = tokens.join(" ")

    scope = scope.merge(Card.name_matching(name)) if name.present?
    scope = scope.merge(Card.in_set_code(code)) if code
    scope = scope.where(set_number: number) if number
    scope
  end

  # Whether a token names a set — asked of `cards.set_name` through the same scope that answers
  # with the set, and **not** of `card_sets`. Resolving it through that table instead is what made
  # this page and SearchCardsTool disagree on all 44 printings whose set was never imported: the
  # tool filtered `cards.set_name` (56 codes) while this refused to read the token as a code at
  # all (30 rows), so `/cards?q=ROS 89` answered Xerosic's Machinations — SFA 89, whose *name*
  # contains "ros" — while the tool answered Sky Field, ROS 89. Reading one column closes that by
  # construction, and it closes the slower version of the same bug too: keyed on `card_sets`, the
  # meaning of a query changed the day an admin imported an unrelated set, silently.
  #
  # Nothing is lost by widening: every `card_sets` row has cards (measured, 0 exceptions), so the
  # 30 are a subset of the 56, and a code with no printing filed under it would answer with no
  # cards whichever way it were read.
  def card_set_code?(token)
    token.match?(SET_CODE_SHAPE) && Card.in_set_code(token).exists?
  end
end
