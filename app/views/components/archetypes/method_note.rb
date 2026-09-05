module Archetypes
  # The page's own footnotes, folded away. Discreet because a reader does not need them to read
  # the report, present because two of the three absences below are absences a reader will
  # otherwise assume are bugs — a deck report elsewhere on the internet has an ACE SPEC line and
  # a "Gust" line, and this one never will.
  class MethodNote < ApplicationComponent
    def view_template
      details(class: "archetype-method") do
        summary { "How this report is built" }

        p do
          plain "Cards are grouped by Cartodex's printing-independent card key, so reprints of "
          plain "one card fold together while two genuinely different cards sharing a name — a "
          plain "Pokémon reprinted with different HP or attacks — stay apart."
        end

        p do
          plain "Categories come from the card's type and from the subtype the scraper records, "
          plain "and from nothing else. There is no ACE SPEC category: nothing in the data "
          plain "isolates one — every ACE SPEC is an Ultra-rarity Trainer and so are dozens of "
          plain "ordinary ones. There are no functional categories either (Gust, Switch, "
          plain "Recovery): what a card does is not recorded anywhere, and guessing it from a "
          plain "name is how a report starts stating things the data never said."
        end

        p do
          plain "Every figure counts what Cartodex holds. An imported standings sheet carries "
          plain "one archetype's rows, so no share of a tournament field can be computed from it."
        end
      end
    end
  end
end
