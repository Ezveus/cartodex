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
      unless @import.failed?
        redirect_to admin_imports_path, alert: "Only failed imports can be retried."
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
