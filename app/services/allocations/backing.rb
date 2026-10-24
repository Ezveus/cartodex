module Allocations
  # How many of a deck row's copies are backed by owned cards, under the app's one backing rule.
  #
  # Every write that lands a copy applies it — Decks::CardAdder on an add,
  # Decks::DeckCardQuantitySetter on an increase, Decks::CopyMover on ⇄, Decks::PrintingSwapper on
  # a swap, Decks::CollectionCopyAdder on "add to my collection and use it here" — and
  # Cards::Printings when it projects a swap for its callers. It lives here, next to
  # Availability, because it is a property of the allocation model rather than of any one write —
  # and because a projection that disagreed with the write would warn the user about the wrong
  # thing.
  module Backing
    # Greedy: claim as many real copies as the collection leaves free to this deck, capped at the
    # row's total, and never below what the deck already backs.
    #
    # `available` must already exclude this deck's own commitments (Availability's
    # `excluding_deck:`), or the deck would be made to compete with itself; `current_owned` is what
    # keeps that exclusion from reading as a ceiling and demoting a real copy on every edit.
    def self.greedy(quantity:, current_owned:, available:)
      [ quantity, [ current_owned, available ].max ].min
    end
  end
end
