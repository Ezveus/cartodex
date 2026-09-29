module Decks
  # Which version a result or a participation about to be written belongs to. Asks the member
  # only when there is a real question: the deck's list has moved on from a version it already
  # has, and nothing else says which list was played.
  #
  # It may snapshot, so every caller runs it inside the same transaction as the save it serves
  # and saves with save! — a version created for a write that then fails must not survive it.
  class VersionResolver < ApplicationService
    # Its message is the sentence the member is shown (Decks::VersionDrift::Result#message), so
    # every surface asking the question prints the same words and none composes its own.
    class ChoiceRequired < StandardError
      attr_reader :current_number, :next_number

      def initialize(current_number, message)
        @current_number = current_number
        @next_number = current_number + 1
        super(message)
      end
    end

    NEW = "new".freeze
    CURRENT = "current".freeze

    def initialize(deck:, choice:, tournament_entry: nil)
      @deck = deck
      @choice = choice.to_s
      @tournament_entry = tournament_entry
    end

    def call
      return @tournament_entry.deck_version if @tournament_entry

      drift = Decks::VersionDrift.call(@deck)
      # No version yet: there is no "version N" to offer, so the first one is taken silently.
      return Decks::VersionSnapshot.call(@deck) if drift.latest.nil?
      return drift.latest unless drift.drift?

      case @choice
      when NEW then Decks::VersionSnapshot.call(@deck)
      when CURRENT then drift.latest
      else
        number = drift.latest.number
        raise ChoiceRequired.new(number, drift.message(number))
      end
    end
  end
end
