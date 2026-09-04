module Admin
  module Imports
    class IndexView < ApplicationComponent
      # How much of an error message the collapsed row shows. Also the threshold below which
      # there is nothing worth disclosing — see error_cell.
      TRUNCATE_AT = 60

      def initialize(imports:)
        @imports = imports
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Imports" }

          render Ui::DataTable.new(columns: %w[ID Kind Label User Status Error Actions]) do |t|
            @imports.each do |imp|
              t.row do
                t.cell { imp.id.to_s }
                t.cell { imp.kind }
                t.cell { imp.label }
                t.cell { imp.user.email }
                t.cell { status_badge(imp) }
                t.cell { error_cell(imp) }
                t.cell { actions_cell(imp) }
              end
            end
          end
        end
      end

      private

      def status_badge(imp)
        render Ui::StatusBadge.new(status: imp.status)
      end

      # A bulk standings run's error_message is a *list* of per-row failures, not a sentence, so
      # the full text has to be readable. It used to live in a `title=` tooltip, which below the
      # 768 px breakpoint is unreachable by construction: Ui::DataTable stacks into a data-label
      # card grid there and a phone has no hover \u2014 the message was, in effect, desktop-only. A
      # <details> discloses it on a tap, at both widths, with no JavaScript.
      def error_cell(imp)
        return plain "\u2014" if imp.error_message.blank?

        # Nothing to disclose when the whole message already fits: a <details> whose body repeats
        # its own summary word for word invites a click that changes nothing.
        if imp.error_message.length <= TRUNCATE_AT
          return plain imp.error_message
        end

        details(class: "import-error") do
          summary { imp.error_message.truncate(TRUNCATE_AT) }
          p(class: "import-error-full") { imp.error_message }
        end
      end

      def actions_cell(imp)
        if imp.failed? || imp.pending?
          link_to "Retry", retry_admin_import_path(imp),
            data: { turbo_method: :post, turbo_confirm: "Retry import #{imp.label}?" },
            class: "btn btn-primary btn-sm"
          plain " "
        end
        # Undo is offered for every bulk run, not only a failed one: the damage this button
        # repairs is rows that were written *successfully* from a wrong deck id or a wrong
        # archetype. It says what it will not do, because it genuinely will not \u2014 a claimed row
        # belongs to the member who claimed it and survives.
        if imp.kind == "limitless_standings"
          link_to "Undo", undo_admin_import_path(imp),
            data: {
              turbo_method: :post,
              turbo_confirm: "Undo import ##{imp.id}? Every standing it created that nobody has " \
                             "claimed will be deleted, along with the field lists attached to them."
            },
            class: "btn btn-secondary btn-sm"
          plain " "
        end
        link_to "Delete", admin_import_path(imp),
          data: { turbo_method: :delete, turbo_confirm: "Delete import ##{imp.id}?" },
          class: "btn-danger btn-sm"
      end
    end
  end
end
