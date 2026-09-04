module Admin
  module StandingsImports
    # What a run would write, before it writes any of it.
    #
    # Every derived value is printed rather than merely used, because each of them is a decision
    # this screen makes on the admin's behalf and each has a failure nothing downstream would
    # catch: a tier guessed wrong files Worlds as a Regional and pays a claimant 350 CP instead of
    # 600; a division guessed wrong writes a second public row for the same player at the same
    # event, which the UNIQUE key cannot see and a corrected re-run cannot fix.
    class PlanTable < ApplicationComponent
      include Phlex::Rails::Helpers::HiddenFieldTag

      # Status → the badge modifier that colours it. Blocked is the only one that borrows the
      # danger treatment: a skip is a normal outcome of a re-run, not a problem.
      STATUS_CLASS = {
        create: "badge-success",
        enrich: "badge-success",
        skip: nil,
        blocked: "badge-danger"
      }.freeze

      STATUS_LABEL = {
        create: "create",
        enrich: "add field list",
        skip: "skip",
        blocked: "blocked"
      }.freeze

      def initialize(plan:, archetype:, deck_id:, event_filters:, limit_per_event:)
        @plan = plan
        @archetype = archetype
        @deck_id = deck_id
        @event_filters = event_filters
        @limit_per_event = limit_per_event
      end

      def view_template
        section(class: "standings-import-plan") do
          h2 { "Plan" }
          totals
          over_limit_notice if @plan.over_limit?
          empty_notice if @plan.events.empty?

          @plan.events.each { |event| event_block(event) }

          confirm_form if confirmable?
        end
      end

      private

      def confirmable? = !@plan.over_limit? && @plan.importable_rows.any?

      def totals
        p(class: "standings-import-totals") do
          plain "#{@plan.total_rows} rows in scope for #{@archetype.name}: "
          count_badge(:create)
          count_badge(:enrich)
          count_badge(:skip)
          count_badge(:blocked)
        end
      end

      def count_badge(status)
        span(class: badge_class(status)) { "#{@plan.count(status)} #{STATUS_LABEL.fetch(status)}" }
        plain " "
      end

      def badge_class(status)
        [ "badge", STATUS_CLASS.fetch(status) ].compact.join(" ")
      end

      # Loud, and it replaces the confirm button rather than sitting beside it: above the ceiling
      # there is nothing to click, because a run of this size is never what an admin meant.
      def over_limit_notice
        div(class: "flash flash-alert standings-import-refusal") do
          plain "#{@plan.importable_rows.size} rows is over the #{@plan.max_rows}-row ceiling for one run. "
          plain "Narrow it with an event filter or a per-event cap, then preview again."
        end
      end

      def empty_notice
        p(class: "settings-empty") { "No event on this page matches those filters." }
      end

      def event_block(event)
        div(class: event_class(event)) do
          h3 { event.name }
          event_meta(event)
          catalog_line(event)
          similar_warning(event)
          blocked_line(event)
          rows_table(event)
        end
      end

      def event_class(event)
        [ "standings-import-event", ("standings-import-event--blocked" if event.blocked?) ].compact.join(" ")
      end

      # Date, tier, format and pool on one line, all four derived and all four correctable only
      # from here — an event this run creates gets them once and keeps them.
      def event_meta(event)
        p(class: "standings-import-event-meta") do
          plain localize(event.date, format: :long)
          plain " · "
          plain tier_label(event)
          plain " · "
          plain format_label(event)
          plain " · "
          plain pool_label(event)
        end
      end

      def tier_label(event)
        Tournament::TIER_LABELS.fetch(event.tier.to_s, event.tier.to_s.humanize)
      end

      def format_label(event)
        return "format Limitless reports is unknown to cartodex" if event.format.blank?
        return event.other_format_name if event.other_format_name.present?

        Tournament::FORMAT_LABELS.fetch(event.format.to_s, event.format.to_s.humanize)
      end

      def pool_label(event)
        return "Standard pool: #{event.standard_pool.name}" if event.standard_pool
        return "no Standard pool needed" unless event.format == "standard"

        "no Standard pool"
      end

      def catalog_line(event)
        p(class: "standings-import-event-catalog") do
          if event.tournament
            plain "Already in the catalog: "
            link_to event.tournament.name, tournament_path(event.tournament)
          else
            plain "Would be created as a new catalog event."
          end
        end
      end

      # A duplicate the UNIQUE key on (name_normalized, date) cannot see: "NAIC 2026" and "NAIC
      # 2026, New Orleans" a day apart are two rows, and one of them becomes undeletable the
      # moment a member records a participation at it.
      def similar_warning(event)
        return if event.similar_tournaments.blank?

        div(class: "flash flash-alert standings-import-duplicate") do
          plain "Possible duplicate — the catalog already holds "
          event.similar_tournaments.each_with_index do |other, index|
            plain ", " if index.positive?
            link_to "#{other.name} (#{other.date})", tournament_path(other)
          end
          plain ". Importing this creates a second event beside it."
        end
      end

      def blocked_line(event)
        return unless event.blocked?

        p(class: "form-error") { "Cannot be imported: #{event.blocked_reason}" }
      end

      def rows_table(event)
        render Ui::DataTable.new(columns: %w[Player Placement Division Status Reason]) do |t|
          event.rows.each do |row_plan|
            t.row do
              t.cell { row_plan.row.player_name.to_s }
              t.cell { row_plan.row.placement&.to_s || "—" }
              t.cell { division_cell(row_plan) }
              t.cell { span(class: badge_class(row_plan.status)) { STATUS_LABEL.fetch(row_plan.status) } }
              t.cell { row_plan.reason.presence || "—" }
            end
          end
        end
      end

      def division_cell(row_plan)
        row = row_plan.row
        plain(row.division || "unreadable (#{row.division_suffix.inspect})")
        return if row_plan.other_division.nil?

        plain " "
        # The same human filed twice: the key is (event, player, division), so a row a member typed
        # under the default Masters and the Senior row this run derives from an /SR suffix collide
        # on nothing and both go public. Which of the two is right is a fact about a person, so it
        # is flagged rather than resolved.
        span(class: "badge badge-warning") do
          "conflict: already recorded as #{row_plan.other_division.division}"
        end
      end

      # The same four inputs again, plus the count the admin actually looked at. Carrying them as
      # hidden fields rather than re-reading the query string keeps the POST self-contained: what
      # runs is what this plan was built from.
      def confirm_form
        form_with(url: admin_standings_imports_path, method: :post, class: "standings-import-confirm") do
          # `id: nil` on every one of them: hidden_field_tag derives an id from the name, and the
          # form above this plan already carries inputs called deck_id, archetype_id,
          # event_filters and limit_per_event. Duplicated ids break `label for=`, make
          # `fill_in "deck_id"` ambiguous, and are invalid HTML besides.
          hidden_field_tag "deck_id", @deck_id, id: nil
          hidden_field_tag "archetype_id", @archetype.id.to_s, id: nil
          hidden_field_tag "event_filters", @event_filters, id: nil
          hidden_field_tag "limit_per_event", @limit_per_event, id: nil
          hidden_field_tag "expected_row_count", @plan.importable_rows.size.to_s, id: nil

          button(type: "submit", class: "btn btn-primary") do
            "Import #{@plan.importable_rows.size} rows as #{@archetype.name}"
          end
        end
      end
    end
  end
end
