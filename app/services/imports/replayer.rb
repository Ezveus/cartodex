module Imports
  # Runs an import again with the parameters it was run with — the Reimport button on
  # /admin/imports. A *new* Import is created and the job enqueued against it; the original row is
  # never touched, so its history, its error and — for a bulk standings run — the receipt its Undo
  # reads all survive.
  #
  # The replay runs as the original import's user, not as the admin who clicked: a deck import
  # lands in that member's decks and their notifications stream.
  #
  # `replay_params` is a json column, so its keys are Strings however they were written; every
  # read below spells them as Strings.
  #
  # Called from Admin:: as ::Imports::Replayer — Admin::Imports is the index view's Phlex namespace
  # and a bare `Imports::Replayer` would resolve to it first.
  class Replayer < ApplicationService
    class Refused < StandardError; end

    # The one kind whose payload is stored and whose replay is still refused, in the words the
    # admin reads. Kept apart from the no-parameters sentence, which would say the opposite.
    RELATIVE_ADD = "A bulk card add cannot be reimported: it adds copies rather than setting them, " \
                   "so replaying it would add them a second time.".freeze

    def initialize(import)
      @import = import
    end

    def call
      refuse!
      # Resolved before the row is written: a kind admitted to REPLAYABLE_KINDS without a branch
      # here must raise with nothing written, not leave a pending row no job will ever finish.
      enqueue = job_for(@import.kind)

      replay = @import.user.imports.create!(
        kind: @import.kind, label: replay_label,
        tournament_id: @import.tournament_id, replay_params: @import.replay_params
      )
      enqueue.call(replay)
      replay
    end

    private

    def refuse!
      raise Refused, RELATIVE_ADD if @import.kind == "bulk_cards"

      unless @import.replayable?
        raise Refused, "Import ##{@import.id} was run before its parameters were stored, so it cannot " \
                       "be reimported — run it again from where it started."
      end

      # The guard Admin::CardSetsController#import applies, minus the row being replayed: a stuck
      # pending row is exactly the one an admin reimports.
      if @import.kind == "card_set" &&
          Import.card_set_imports.pending.where.not(id: @import.id).exists?(label: @import.label)
        raise Refused, "Set #{@import.label} is already being imported."
      end
    end

    # The original's label, except where it names a value the replay will not use. A card-label
    # import's label spells the search token, while the job runs whatever token the label carries
    # *now* — an admin may have edited it since — so the row, its summary and its flash would
    # otherwise name a search that was never run. A label deleted since keeps the old text; the job
    # then fails the row with "That card label no longer exists."
    def replay_label
      return @import.label unless @import.kind == "card_labels"

      card_label = CardLabel.find_by(id: @import.replay_params["card_label_id"])
      card_label ? "#{card_label.name} (#{card_label.source_query})" : @import.label
    end

    def job_for(kind)
      params = @import.replay_params
      user = @import.user

      case kind
      when "deck"
        ->(replay) { ::Decks::ImportJob.perform_later(params["decklist"], user, params["name"], replay) }
      when "card_set"
        ->(replay) { ::CardSets::ImportJob.perform_later(params["url"], user, replay) }
      when "standing_list"
        ->(replay) {
          ::Tournaments::StandingListImportJob.perform_later(params["standing_id"], params["decklist"], user.id, replay.id)
        }
      when "limitless_standings"
        ->(replay) { ::Tournaments::LimitlessImportJob.perform_later(replay.id, user.id, params) }
      when "card_labels"
        ->(replay) { ::CardLabels::ImportJob.perform_later(replay.id, params["card_label_id"], user.id) }
      else
        raise ArgumentError, "no replay is written for #{kind} imports"
      end
    end
  end
end
