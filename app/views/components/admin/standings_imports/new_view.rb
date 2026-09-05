module Admin
  module StandingsImports
    # The whole screen: the form, and — once a preview has run — the plan it produced.
    #
    # One view for both because they are one page: the plan is an answer to the form still sitting
    # above it, and an admin who reads "this event has no Standard pool" needs the filter field in
    # the same viewport to narrow the run and try again.
    class NewView < ApplicationComponent
      def initialize(deck_id:, archetype_id:, event_filters:, limit_per_event:, archetypes:,
                     plan: nil, archetype: nil)
        @deck_id = deck_id
        @archetype_id = archetype_id
        @event_filters = event_filters
        @limit_per_event = limit_per_event
        @archetypes = archetypes
        @plan = plan
        @archetype = archetype
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Import standings from Limitless")
          lead

          render Admin::StandingsImports::Form.new(
            deck_id: @deck_id, archetype_id: @archetype_id, event_filters: @event_filters,
            limit_per_event: @limit_per_event, archetypes: @archetypes
          )

          if @plan
            render Admin::StandingsImports::PlanTable.new(
              plan: @plan, archetype: @archetype, deck_id: @deck_id,
              event_filters: @event_filters, limit_per_event: @limit_per_event
            )
          end
        end
      end

      private

      def lead
        p(class: "settings-section-lead") do
          plain "Reads one archetype's tournament history off limitlesstcg.com and turns it into "
          plain "public standings rows. Preview first: everything a run writes lands in the "
          plain "catalog every member reads, where nothing tells an import from a hand-typed row."
        end
      end
    end
  end
end
