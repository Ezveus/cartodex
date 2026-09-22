module Admin
  module StandingsImports
    # The whole screen: the form, and — once a preview has run — the plan it produced.
    #
    # One view for both because they are one page: the plan is an answer to the form still sitting
    # above it, and an admin who reads "this event has no Standard pool" needs the filter field in
    # the same viewport to narrow the run and try again.
    class NewView < ApplicationComponent
      def initialize(source:, deck_id:, slug:, rotation:, set:, archetype_id:, event_filters:,
                     limit_per_event:, archetypes:, plan: nil, archetype: nil, tournament_id: nil,
                     mapping_lines: nil)
        @source = source
        @tournament_id = tournament_id
        @mapping_lines = mapping_lines
        @deck_id = deck_id
        @slug = slug
        @rotation = rotation
        @set = set
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
            source: @source, tournament_id: @tournament_id, deck_id: @deck_id, slug: @slug,
            rotation: @rotation, set: @set, archetype_id: @archetype_id,
            event_filters: @event_filters, limit_per_event: @limit_per_event, archetypes: @archetypes
          )

          plan_section if @plan
        end
      end

      private

      # A whole-event run arbitrates its decks and approves its plan in one POST, so its confirm
      # form wraps both; the two older sources have nothing to arbitrate and the plan table owns
      # its own.
      def plan_section
        if @mapping_lines
          render Admin::StandingsImports::EventConfirmForm.new(
            plan: @plan, mapping_lines: @mapping_lines, archetypes: @archetypes, source: @source,
            tournament_id: @tournament_id, event_filters: @event_filters,
            limit_per_event: @limit_per_event
          )
        else
          render Admin::StandingsImports::PlanTable.new(
            plan: @plan, archetype: @archetype, source: @source, deck_id: @deck_id,
            slug: @slug, rotation: @rotation, set: @set,
            event_filters: @event_filters, limit_per_event: @limit_per_event
          )
        end
      end

      def lead
        p(class: "settings-section-lead") do
          plain "Reads results off limitlesstcg.com — one archetype's paper tournament history, "
          plain "its best online finishes in one card pool, or one whole event, every division — "
          plain "and turns them into public standings rows. Preview first: everything a run writes "
          plain "lands in the catalog every member reads, where nothing tells an import from a "
          plain "hand-typed row."
        end
      end
    end
  end
end
