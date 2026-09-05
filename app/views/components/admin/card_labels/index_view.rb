module Admin
  module CardLabels
    class IndexView < ApplicationComponent
      def initialize(card_labels:, assignment_counts:)
        @card_labels = card_labels
        @assignment_counts = assignment_counts
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Card Labels") do
            link_to "New Label", new_admin_card_label_path, class: "btn btn-primary"
          end

          render Ui::DataTable.new(
            columns: [ "Label", "Family", "Slug", "Search", "Cards", "Actions" ]
          ) do |t|
            @card_labels.each { |label| row(t, label) }
          end
        end
      end

      private

      def row(t, label)
        t.row do
          t.cell { label.name }
          t.cell { label.family }
          t.cell { label.slug }
          t.cell { label.source_query.presence || "—" }
          t.cell { @assignment_counts.fetch(label.id, 0).to_s }
          t.cell { actions(label) }
        end
      end

      # A role label carries no delete link at all, rather than one the controller then refuses:
      # the refusal is the rule, and a button that only ever says no is a worse way to state it.
      def actions(label)
        div(class: "admin-actions") do
          button_to("Import", import_admin_card_label_path(label), class: "btn btn-secondary btn-sm") if label.importable?
          link_to "Edit", edit_admin_card_label_path(label), class: "btn btn-secondary btn-sm"
          unless label.role?
            button_to "Delete", admin_card_label_path(label), method: :delete,
              class: "btn btn-danger btn-sm",
              form: { data: { turbo_confirm: "Delete #{label.name} and its assignments?" } }
          end
        end
      end
    end
  end
end
