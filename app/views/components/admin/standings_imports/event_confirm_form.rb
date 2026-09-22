module Admin
  module StandingsImports
    # The arbitration and the plan, inside one POST.
    #
    # One form around both halves rather than two beside each other, because they are one decision:
    # the selects above are what unblock the rows below, and a plan submitted without them would
    # import an event every one of whose rows is refused. That is also why the button does not
    # name a count the way the other two sources' does — the count on screen is the count *before*
    # the mappings are stored, and confirming is precisely what changes it.
    class EventConfirmForm < ApplicationComponent
      def initialize(plan:, mapping_lines:, archetypes:, source:, tournament_id:, event_filters:,
                     limit_per_event:)
        @plan = plan
        @mapping_lines = mapping_lines
        @archetypes = archetypes
        @source = source
        @tournament_id = tournament_id
        @event_filters = event_filters
        @limit_per_event = limit_per_event
      end

      def view_template
        form_with(url: admin_standings_imports_path, method: :post, class: "standings-import-confirm") do
          # Carried rather than re-read off the query string, so what runs is what this plan was
          # built from — the source included, since a run that lost it would silently become a
          # paper one. No id on any of them: the form above this one already owns those ids.
          input(type: "hidden", name: "source", value: @source)
          input(type: "hidden", name: "tournament_id", value: @tournament_id)
          input(type: "hidden", name: "event_filters", value: @event_filters)
          input(type: "hidden", name: "limit_per_event", value: @limit_per_event)

          render Admin::StandingsImports::MappingTable.new(lines: @mapping_lines, archetypes: @archetypes)
          render Admin::StandingsImports::PlanTable.new(
            plan: @plan, archetype: nil, source: @source, event_filters: @event_filters,
            limit_per_event: @limit_per_event, confirm: false
          )

          div(class: "form-actions standings-import-confirm-actions") do
            button(type: "submit", class: "btn btn-primary") { "Confirm mappings and import" }
          end
        end
      end
    end
  end
end
