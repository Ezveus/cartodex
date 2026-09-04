module Admin
  class ImportsController < BaseController
    before_action :set_import, only: [ :destroy, :retry ]

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

      # The decklist text is not stored anywhere — an Import carries a label, not a payload — so
      # there is nothing to re-run. Refused here rather than left to fall through the `case`
      # below, which destroys the old row and enqueues nothing. (The "deck" branch has had that
      # bug since it was written: it re-enqueues @import.label as the *decklist*, which is the
      # deck's name. Pre-existing and out of scope — recorded so the new kind is not wired into
      # the same switch and left silently doing nothing.)
      if @import.kind == "standing_list"
        redirect_to admin_imports_path,
          alert: "A tournament field list cannot be retried: its decklist text is not stored."
        return
      end

      new_import = @import.user.imports.create!(kind: @import.kind, label: @import.label)

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

    private

    def set_import
      @import = Import.find(params[:id])
    end
  end
end
