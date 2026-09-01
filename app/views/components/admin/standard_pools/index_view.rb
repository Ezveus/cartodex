module Admin
  module StandardPools
    class IndexView < ApplicationComponent
      # The counts arrive as {standard_pool_id => n} hashes rather than being read off
      # the associations: the index prints two integers per row, and loading every
      # anchored deck and tournament to produce them is a payload nobody looks at.
      def initialize(standard_pools:, deck_counts:, tournament_counts:)
        @standard_pools = standard_pools
        @deck_counts = deck_counts
        @tournament_counts = tournament_counts
        @current = StandardPool.current
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Standard Pools") do
            link_to "New Pool", new_admin_standard_pool_path, class: "btn btn-primary"
          end

          render Ui::DataTable.new(
            columns: [ "Pool", "Marks", "Released", "Legal", "Decks", "Tournaments", "Actions" ]
          ) do |t|
            @standard_pools.each { |pool| row(t, pool) }
          end
        end
      end

      private

      # The deck and tournament counts are what make a refused deletion legible
      # before it is attempted: both associations are restrict_with_error.
      def row(t, pool)
        t.row do
          t.cell { pool == @current ? "#{pool.name} (current)" : pool.name }
          t.cell { pool.regulation_marks.join(", ") }
          t.cell { pool.released_on.strftime("%Y-%m-%d") }
          t.cell { pool.legal_on.strftime("%Y-%m-%d") }
          t.cell { @deck_counts.fetch(pool.id, 0).to_s }
          t.cell { @tournament_counts.fetch(pool.id, 0).to_s }
          t.cell do
            render Ui::AdminActions.new(
              edit_path: edit_admin_standard_pool_path(pool),
              delete_path: admin_standard_pool_path(pool),
              confirm_message: "Delete #{pool.name}?"
            )
          end
        end
      end
    end
  end
end
