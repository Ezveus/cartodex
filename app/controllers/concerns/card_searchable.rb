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
    # Where the two readings collide the set wins, and that is a deliberate loss: 11 of the 28 set
    # codes are also substrings of card names, so "Mew 25" now answers with MEW 25 rather than
    # with a card named Mew. "MEG 113" is how a player writes a printing; "name contains this
    # 2-5 letter fragment *and* carries this number" is a coincidence filter nobody types on
    # purpose. Returning the union of both readings was weighed and refused — it keeps a query
    # answering three cards where the reader asked for one.
    number = tokens.pop if tokens.length > 1 && tokens.last.match?(/\A\d+\z/)
    code   = tokens.pop if (tokens.length > 1 || number) && card_set_code?(tokens.last)
    name   = tokens.join(" ")

    scope = scope.merge(Card.name_matching(name)) if name.present?
    scope = scope.where("UPPER(cards.set_name) = ?", code.upcase) if code
    scope = scope.where(set_number: number) if number
    scope
  end

  def card_set_code?(token)
    token.match?(/\A[a-zA-Z]{2,5}\z/) &&
      CardSet.where("UPPER(code) = ?", token.upcase).exists?
  end
end
