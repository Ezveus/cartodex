module Archetypes
  # "4 copies", "1-3 copies · most often 2" — how many of a thing the lists play, and how settled
  # that number is.
  #
  # A module rather than a method on one component because two things answer the same question at
  # two grains: an `Entry` (this card, in the lists that play it) and a `CategoryGroup` (this
  # section, in every list of the sample). Both carry `min_copies`, `max_copies`, `modes`,
  # `single_quantity?` and `tied_mode?` under those names precisely so one text can serve them,
  # and the alternative — two copies of the same four methods — is how a page comes to print
  # "1 copies" in one place and "1 copy" in another.
  #
  # What the two do not share is the rule behind the numbers: an entry's range is the range
  # **when played**, a section's runs over every list including the ones playing none. That
  # difference lives in Archetypes::CardStats, not here; this only prints what it is handed.
  module CopiesText
    private

    def copies_text(subject)
      parts = [ "#{copies_range(subject)} #{copies_noun(subject)}" ]
      parts << mode_text(subject) unless subject.single_quantity?
      parts.join(" · ")
    end

    def copies_range(subject)
      return subject.min_copies.to_s if subject.single_quantity?

      "#{subject.min_copies}-#{subject.max_copies}"
    end

    def copies_noun(subject)
      subject.single_quantity? && subject.min_copies == 1 ? "copy" : "copies"
    end

    # A tie is a real answer and is said to be one. Printing "3 / 4" alone reads as a range or a
    # typo; silently picking 3 would state a consensus this sample does not hold.
    def mode_text(subject)
      return "most often #{subject.modes.join(' / ')} — tied" if subject.tied_mode?

      "most often #{subject.modes.first}"
    end
  end
end
