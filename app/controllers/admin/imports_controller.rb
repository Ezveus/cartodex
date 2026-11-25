module Admin
  class ImportsController < BaseController
    before_action :set_import, only: [ :destroy, :reimport, :undo ]

    def index
      @imports = Import.includes(:user).order(created_at: :desc)
    end

    def destroy
      @import.destroy
      redirect_to admin_imports_path, notice: "Import deleted."
    end

    # Runs the import again with what it was run from, as a new row beside this one — see
    # Imports::Replayer for what it refuses and why the original is kept. Any status: replaying a
    # *completed* bulk standings run is the main case, the way new lists of an archetype come in.
    def reimport
      replay = ::Imports::Replayer.call(@import)
      redirect_to admin_imports_path, notice: "Reimported as import ##{replay.id}."
    rescue ::Imports::Replayer::Refused => e
      redirect_to admin_imports_path, alert: e.message
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
