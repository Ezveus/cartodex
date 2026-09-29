module Decks
  # Records one match result against the version it was played with. The service exists for its
  # transaction: Decks::VersionResolver may snapshot the deck, and that snapshot must roll back
  # with a result that then fails validation — a false `save` does not roll anything back, so the
  # save is save! and its RecordInvalid is caught outside the block.
  #
  # ChoiceRequired is let through: asking the member is the caller's job, and nothing has been
  # written by the time it is raised.
  class ResultRecorder < ApplicationService
    Result = Struct.new(:result, :errors)

    def initialize(deck:, attributes:, choice:)
      @deck = deck
      @attributes = attributes
      @choice = choice
    end

    def call
      result = @deck.deck_results.build(@attributes)
      result.played_at ||= Time.current

      serialized_transaction do
        result.deck_version = Decks::VersionResolver.call(
          deck: @deck, choice: @choice, tournament_entry: own_entry(result)
        )
        result.save!
      end

      Result.new(result, [])
    rescue ActiveRecord::RecordInvalid
      Result.new(result, result.errors.full_messages)
    ensure
      # A refused result stays built on the association otherwise, and the caller's next count of
      # @deck.deck_results would include it.
      @deck.deck_results.reset unless result&.persisted?
    end

    private

    # Only a participation of this deck answers the question. Any other is refused by
    # DeckResult#entry_belongs_to_same_deck; resolving through it first would file the result on
    # another deck's version and add a second, misleading error beside the real one.
    def own_entry(result)
      entry = result.tournament_entry
      entry if entry&.deck_id == @deck.id
    end
  end
end
