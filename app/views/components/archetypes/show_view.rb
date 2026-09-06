module Archetypes
  # The metagame page of one archetype: who it is, which sample the reader is looking at, what it
  # has been recorded doing, and what its recorded lists play.
  #
  # Every number on this page is a count of what Cartodex holds, never a share of a field. A
  # standings sheet imported from one archetype's Limitless page contains only that archetype's
  # rows, so the database never sees the rest of the event and cannot produce a metagame share —
  # which is why the performance panel's heading says "recorded in Cartodex" rather than naming
  # the field, and why no component here divides by anything but the sample.
  #
  # The four collaborators are handed in whole rather than rebuilt: Archetypes::MetagameScope
  # decides which standings count, and letting a view ask that question a second time is how the
  # panel and the report end up describing two different populations.
  class ShowView < ApplicationComponent
    def initialize(archetype:, scope:, stats:, performance:)
      @archetype = archetype
      @scope = scope
      @stats = stats
      @performance = performance
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: @archetype.name) do
          div(class: "decks-header-actions") do
            render Ui::ArchetypeBadge.new(archetype: @archetype)
            link_to "Back to Archetypes", archetypes_path, class: "btn btn-secondary"
          end
        end

        render Archetypes::Identity.new(archetype: @archetype)
        render Archetypes::SampleSelector.new(scope: @scope, grouping: @stats.grouping)
        render Archetypes::PerformancePanel.new(performance: @performance)
        render Archetypes::CardReport.new(stats: @stats, scope: @scope)
        render Archetypes::MethodNote.new
      end
    end
  end
end
