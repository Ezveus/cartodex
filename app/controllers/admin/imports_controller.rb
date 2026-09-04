module Admin
  class ImportsController < BaseController
    before_action :set_import, only: [ :destroy, :retry, :undo ]

    # An allowlist, not a list of refusals. An Import carries a label, never the payload it was
    # run from, so a kind is retryable only when its label happens to be enough to reconstruct the
    # whole job — which is true of exactly these two and was never true of anything else. Spelled
    # this way round because the `case` below has no `else`: with a refusal list, a kind added
    # tomorrow and forgotten here would fall straight through it, destroying the old row and
    # enqueueing nothing — a button that reports "Import retried." and does not.
    RETRYABLE_KINDS = %w[deck card_set].freeze

    # Why each known kind is refused, in the wording the admin sees. The fallback below covers a
    # kind nobody has written a sentence for yet: vaguer, but still a refusal.
    UNRETRYABLE_REASONS = {
      "standing_list" => "A tournament field list cannot be retried: its decklist text is not stored.",
      "limitless_standings" => "A bulk standings import cannot be retried: the run's filters are not stored. " \
                               "Run it again from the import form."
    }.freeze

    def index
      @imports = Import.includes(:user).order(created_at: :desc)
    end

    def destroy
      @import.destroy
      redirect_to admin_imports_path, notice: "Import deleted."
    end

    def retry
      unless @import.failed? || @import.pending?
        redirect_to admin_imports_path, alert: "Only failed or pending imports can be retried."
        return
      end

      unless RETRYABLE_KINDS.include?(@import.kind)
        redirect_to admin_imports_path, alert: unretryable_reason(@import)
        return
      end

      new_import = @import.user.imports.create!(kind: @import.kind, label: @import.label)

      # (The "deck" branch has had a bug since it was written: it re-enqueues @import.label as the
      # *decklist*, which is the deck's name. Pre-existing and out of scope — recorded here so the
      # allowlist above is not read as a claim that both branches work.)
      case @import.kind
      when "deck"
        ::Decks::ImportJob.perform_later(@import.label, @import.user, @import.label, new_import)
      when "card_set"
        url = "https://limitlesstcg.com/cards/#{@import.label}"
        ::CardSets::ImportJob.perform_later(url, @import.user, new_import)
      end

      @import.destroy
      redirect_to admin_imports_path, notice: "Import retried."
    end

    # The only way back out of a bad bulk run — see Tournaments::StandingsImportUndo for what it
    # leaves alone and why. Refused for every other kind rather than silently doing nothing: no
    # other import records what it created, so there is nothing an undo could act on.
    def undo
      unless @import.kind == "limitless_standings"
        redirect_to admin_imports_path, alert: "Only a bulk standings import can be undone."
        return
      end

      result = ::Tournaments::StandingsImportUndo.call(@import)
      redirect_to admin_imports_path, notice: undo_notice(result)
    end

    private

    def set_import
      @import = Import.find(params[:id])
    end

    def unretryable_reason(import)
      UNRETRYABLE_REASONS.fetch(import.kind) do
        "A #{import.kind} import cannot be retried: what it was run from is not stored."
      end
    end

    # Names both counts, always: "nothing was undone" and "everything was undone" are different
    # answers to the same click, and the claimed rows are the half the admin has to go and look
    # at by hand.
    def undo_notice(result)
      parts = [ "Undid #{helpers.pluralize(result.destroyed, 'standing')}" ]
      # Named separately because it is a different act on somebody else's row: the run attached a
      # field list to a standing it did not create, and undo takes only that back.
      parts << "took the field list back off #{helpers.pluralize(result.detached, 'existing standing')}" if
        result.detached.positive?
      if result.kept_claimed.positive?
        was_were = result.kept_claimed == 1 ? "was" : "were"
        parts << "#{result.kept_claimed} #{was_were} claimed and kept"
      end
      "#{parts.join("; ")}."
    end
  end
end
