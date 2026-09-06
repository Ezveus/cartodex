module Archetypes
  # The page's own footnotes, folded away. Discreet because a reader does not need them to read
  # the report, present because what they describe is otherwise assumed to be a bug: a deck report
  # elsewhere on the internet has an ACE SPEC line and a "Gust" line, and this one answers both
  # questions differently — the first as a badge that opens no section, the second as a whole
  # second grouping whose sections deliberately overlap.
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
          plain "Grouped by type, the sections come from the card's type and from the subtype the "
          plain "scraper records, and from nothing else. There is no ACE SPEC category: nothing "
          plain "in the data isolates one — every ACE SPEC is an Ultra-rarity Trainer and so are "
          plain "dozens of ordinary ones — so it is a badge on the card's line, which takes it "
          plain "out of no section."
        end

        p do
          plain "Grouped by role, the sections say what a card does (Draw, Search, Gust, Switch, "
          plain "Recovery, Disruption, Energy acceleration). A role is a property of the card and "
          plain "not of the deck playing it, and it is recorded rather than guessed: a rule reads "
          plain "the card's own text and proposes, and a person decides. Guessing a card's "
          plain "function from its name at the moment of rendering is how a report starts stating "
          plain "things the data never said, so a card nobody has decided about says exactly that "
          plain "— it is listed under “No role recorded” rather than filed by its type. A card "
          plain "with two roles is listed under both, so those sections add up to more than a "
          plain "list."
        end

        p do
          plain "Every figure counts what Cartodex holds. An imported standings sheet carries "
          plain "one archetype's rows, so no share of a tournament field can be computed from it."
        end
      end
    end
  end
end
