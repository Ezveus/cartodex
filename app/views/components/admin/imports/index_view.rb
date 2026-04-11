module Admin
  module Imports
    class IndexView < ApplicationComponent
      def initialize(imports:)
        @imports = imports
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Imports" }

          render Ui::AdminTable.new(columns: %w[ID Kind Label User Status Error Actions]) do
            @imports.each do |imp|
              tr do
                td { imp.id.to_s }
                td { imp.kind }
                td { imp.label }
                td { imp.user.email }
                td { status_badge(imp) }
                td { error_cell(imp) }
                td { actions_cell(imp) }
              end
            end
          end
        end
      end

      private

      def status_badge(imp)
        css = case imp.status
        when "pending" then "badge badge-warning"
        when "completed" then "badge badge-success"
        when "failed" then "badge badge-danger"
        end
        span(class: css) { imp.status }
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
          link_to "Retry", helpers.retry_admin_import_path(imp),
            data: { turbo_method: :post, turbo_confirm: "Retry import #{imp.label}?" },
            class: "btn btn-primary btn-sm"
          plain " "
        end
        link_to "Delete", helpers.admin_import_path(imp),
          data: { turbo_method: :delete, turbo_confirm: "Delete import ##{imp.id}?" },
          class: "btn-danger btn-sm"
      end
    end
  end
end
