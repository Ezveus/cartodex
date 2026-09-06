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
      #
      # link_to with a data-turbo-method, not button_to: button_to renders a block-level <form>,
      # which stacks vertically under any parent — wrapping it in a div changes nothing, since
      # block children stack in normal flow regardless of nesting. ".admin-actions" is also not a
      # class this app defines anywhere (the only neighbour, ".admin-header-actions", is a page
      # header's row, not a table cell's). Ui::AdminActions and Admin::Imports::IndexView's own
      # actions_cell are the precedent in this same panel: no wrapper, every control an <a>, plain
      # " " between them, so they lay out inline on one line inside the cell.
      def actions(label)
        if label.importable?
          link_to "Import", import_admin_card_label_path(label),
            data: { turbo_method: :post }, class: "btn btn-secondary btn-sm"
          plain " "
        end
        link_to "Edit", edit_admin_card_label_path(label), class: "btn btn-secondary btn-sm"
        unless label.role?
          plain " "
          link_to "Delete", admin_card_label_path(label),
            data: { turbo_method: :delete, turbo_confirm: "Delete #{label.name} and its assignments?" },
            class: "btn btn-danger btn-sm"
        end
      end
    end
  end
end
