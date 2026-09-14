module CardSearchable
  extend ActiveSupport::Concern

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
    # Where the two readings collide the set wins, and that is a deliberate loss: 12 of the 28
    # imported set codes are also substrings of card names, so "Mew 25" now answers with MEW 25
    # rather than with a card named Mew. "MEG 113" is how a player writes a printing; "name
    # contains this 2-5 letter fragment *and* carries this number" is a coincidence filter nobody
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
  # tool filtered `cards.set_name` (54 codes) while this refused to read the token as a code at
  # all (28 rows), so `/cards?q=ROS 89` answered Xerosic's Machinations — SFA 89, whose *name*
  # contains "ros" — while the tool answered Sky Field, ROS 89. Reading one column closes that by
  # construction, and it closes the slower version of the same bug too: keyed on `card_sets`, the
  # meaning of a query changed the day an admin imported an unrelated set, silently.
  #
  # Nothing is lost by widening: every `card_sets` row has cards (measured, 0 exceptions), so the
  # 28 are a subset of the 54, and a code with no printing filed under it would answer with no
  # cards whichever way it were read.
  def card_set_code?(token)
    token.match?(/\A[a-zA-Z]{2,5}\z/) && Card.in_set_code(token).exists?
  end
end
