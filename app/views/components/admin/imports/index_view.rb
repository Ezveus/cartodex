module Admin
  module Imports
    class IndexView < ApplicationComponent
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

      def error_cell(imp)
        if imp.error_message.present?
          span(title: imp.error_message, style: "cursor: help;") do
            plain imp.error_message.truncate(60)
          end
        else
          plain "\u2014"
        end
      end

      def actions_cell(imp)
        if imp.failed? || imp.pending?
          link_to "Retry", retry_admin_import_path(imp),
            data: { turbo_method: :post, turbo_confirm: "Retry import #{imp.label}?" },
            class: "btn btn-primary btn-sm"
          plain " "
        end
        link_to "Delete", admin_import_path(imp),
          data: { turbo_method: :delete, turbo_confirm: "Delete import ##{imp.id}?" },
          class: "btn-danger btn-sm"
      end
    end
  end
end
