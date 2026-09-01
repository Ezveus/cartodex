module Admin
  module StandardPools
    class IndexView < ApplicationComponent
      def initialize(standard_pools:)
        @standard_pools = standard_pools
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
          t.cell { pool.decks.size.to_s }
          t.cell { pool.tournaments.size.to_s }
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
