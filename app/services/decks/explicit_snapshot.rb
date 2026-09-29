module Decks
  # The member's explicit "New version": the live list becomes the next version, provided it has
  # moved on from the latest one — without drift it would record a duplicate. The check and the
  # write share one serialized transaction, so two concurrent clicks cannot both see drift and
  # both record the same list.
  class ExplicitSnapshot < ApplicationService
    # `version` is the one recorded, nil when refused; `latest` is what the deck still matches then.
    Result = Struct.new(:version, :latest)

    def initialize(deck)
      @deck = deck
    end

    def call
      serialized_transaction do
        drift = Decks::VersionDrift.call(@deck)
        next Result.new(nil, drift.latest) if drift.latest && !drift.drift?

        Result.new(Decks::VersionSnapshot.call(@deck), drift.latest)
      end
    end
  end
end
