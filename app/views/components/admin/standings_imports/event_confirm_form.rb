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

          confirm_action
        end
      end

      private

      # The button survives every row being blocked — that is the ordinary first preview, and
      # confirming the decks above is exactly what unblocks them. It does **not** survive the
      # *event* being blocked: nothing on this page can lift an event-level refusal (a pool that
      # disagrees with the catalogue, a format cartodex cannot read), so the button would enqueue a
      # run that writes nothing and reports it afterwards. The other two sources withhold theirs on
      # `importable_rows.empty?`; this one has to ask the narrower question, or it would withhold it
      # on the one screen where blocked rows are the point.
      def confirm_action
        return blocked_action if @plan.events.any?(&:blocked?)
        return over_limit_action if @plan.over_limit?

        div(class: "form-actions standings-import-confirm-actions") do
          button(type: "submit", class: "btn btn-primary") { "Confirm mappings and import" }
        end
      end

      def blocked_action
        div(class: "flash flash-alert standings-import-refusal") do
          plain "Nothing here can be imported until the event itself is corrected. "
          plain "Confirming decks would not change that."
        end
      end

      # Nor does it survive the *ceiling*, and that had to be asked here rather than inherited.
      # PlanTable prints the notice whatever `confirm:` says, but the button it withholds alongside
      # it is its own — and this source renders it with `confirm: false`, so `PlanTable#confirmable?`
      # (which does test `over_limit?`) is never consulted for it. The first preview cannot reach
      # the ceiling, because every row of an unmapped deck is blocked and `importable_rows` is 0;
      # the *second* one — where confirming the decks has finally made the rows count — rendered
      # "N rows is over the 1000-row ceiling" with a working button directly beneath it. The click
      # enqueues a run that raises PlanTooLarge and writes nothing, and the next preview makes the
      # same offer again. EVENT_MAX_ROWS is 1000 against a largest Limitless event of 3752 players,
      # so this is an ordinary major Regional and not a corner.
      #
      # Its own sentence, because the notice above names an event filter as a way out: true of the
      # two sources whose run covers a page of events, false of this one, which covers one event by
      # construction. The per-event cap is the only lever, so it is the only one named.
      def over_limit_action
        div(class: "flash flash-alert standings-import-refusal") do
          plain "#{@plan.importable_rows.size} rows is over the #{@plan.max_rows}-row ceiling for "
          plain "one run. Set a top-N-per-event cap above and preview again — a whole-event run "
          plain "covers one event, so no event filter can narrow it."
        end
      end
    end
  end
end
