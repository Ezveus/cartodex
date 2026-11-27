module Cards
  # How the card is played across the recorded field, as a tree: archetype, then Standard pool,
  # then tournament, each node printing the figure `/archetypes/:slug/analysis` prints for this card
  # under the same sample — and linking to that page, with exactly those parameters, so the reader
  # can check it. Cards::ArchetypeUsage computes it; see that class and
  # docs/superpowers/specs/2026-11-25-card-archetype-usage-design.md.
  #
  # Nested <details>, all collapsed: a card played everywhere (Boss's Orders) has 82 archetypes and
  # 1104 tournament leaves, and the first level alone is what a reader scans.
  class UsageSection < ApplicationComponent
    include Archetypes::CopiesText

    def initialize(card:, usage:)
      @card = card
      @usage = usage
    end

    def view_template
      section(class: "card-info-section card-usage", id: "usage") do
        h2 { "Played in recorded lists" }
        intro
        filters if any_filter?

        if @usage.any?
          ul(class: "card-usage-tree") { @usage.archetypes.each { |node| archetype_item(node) } }
        else
          p(class: "card-usage-empty") { "No recorded list plays this card." }
        end
      end
    end

    private

    # Three sentences, each answering a review finding about what the figures claim. Every linked
    # node is the analysis's figure for the same sample — "Other formats" has no such sample. An
    # archetype's first line covers the sample the filters select, which under All formats counts
    # every rotation together, as the analysis's "All formats" does, and says so on the line itself.
    # And the analysis's two qualifiers — a small-sample notice under MetagameScope::SMALL_SAMPLE
    # lists, and the note that paper and online lists are counted together — apply here as much as
    # there: on a production copy, two thirds of the linked nodes hold fewer than 10 lists.
    def intro
      div(class: "card-usage-intro") do
        p do
          plain "The share of each sample's lists recorded in Cartodex that play this card, in any " \
                "printing. Every line with an Analysis link is the figure the archetype's analysis " \
                "prints for the same sample."
        end
        p do
          plain "An archetype's first line covers the sample the filters select. Under All formats " \
                "it counts every format and rotation together, as the analysis's All formats does; " \
                "open it, or choose a Standard pool, for one rotation at a time."
        end
        p do
          plain "Below #{Archetypes::MetagameScope::SMALL_SAMPLE} lists a percentage rests on a " \
                "handful of lists, and unless a venue is chosen, paper and online lists are " \
                "counted together. A filter's own counts ignore the filters after it: the " \
                "Standard pool counts span both venues and every tournament, the Venue counts " \
                "every tournament."
        end
      end
    end

    def any_filter?
      @usage.pool_selectable? || @usage.venue_selectable? || @usage.tournament_selectable?
    end

    # A GET back onto this page, anchored on the section so the reload lands where the reader was.
    # One form for the three selects, as Archetypes::SampleSelector has one: the form replaces the
    # whole query string, so a change to one select carries the other two along, and the service's
    # clamps settle any that the change left behind. Each select renders only where its own axis is
    # a choice, and each reads its `selected:` off the Result, never off the parameter.
    def filters
      form(action: "#{card_path(@card)}#usage", method: "get", class: "deck-filters card-usage-filters",
           data: { controller: "card-filter" }) do
        filter_select("Standard pool", "pool", @usage.pool_options, @usage.pool&.id&.to_s || Cards::ArchetypeUsage::ALL) if @usage.pool_selectable?
        filter_select("Venue", "venue", @usage.venue_options, @usage.venue.to_s) if @usage.venue_selectable?
        if @usage.tournament_selectable?
          filter_select("Tournament", "tournament", @usage.tournament_options,
                        @usage.tournament_id&.to_s || Cards::ArchetypeUsage::ALL)
        end
      end
    end

    def filter_select(caption, name, options, selected)
      label(class: "archetype-sample-label") do
        span { caption }
        render Ui::FilterSelect.new(name: name, options: options.map { |option| [ option.label, option.value ] },
                                    selected: selected)
      end
    end

    # Under one tournament the archetype's line is the whole answer, so it is a leaf rather than a
    # <details> with nothing inside. An unplayed count never stands alone: an archetype is listed
    # only where the selection holds a list playing the card, so under a pool it has a played event.
    def archetype_item(node)
      li(class: "card-usage-node card-usage-archetype") do
        if node.pools.empty? && node.tournaments.empty?
          node_line(node.archetype.name, node.usage, node.analysis_params, node.archetype, scope: node.scope_label)
        else
          details do
            summary do
              node_line(node.archetype.name, node.usage, node.analysis_params, node.archetype,
                        scope: node.scope_label)
            end
            ul(class: "card-usage-children") do
              node.pools.each { |pool| pool_item(pool, node.archetype) }
              tournament_items(node.tournaments, node.unplayed_tournaments_count, node.archetype)
            end
          end
        end
      end
    end

    def pool_item(node, archetype)
      li(class: "card-usage-node card-usage-pool") do
        details do
          summary { node_line(node.label, node.usage, node.analysis_params, archetype) }
          ul(class: "card-usage-children") do
            tournament_items(node.tournaments, node.unplayed_tournaments_count, archetype)
          end
        end
      end
    end

    def tournament_items(tournaments, unplayed_count, archetype)
      tournaments.each do |tournament|
        li(class: "card-usage-node card-usage-tournament") do
          node_line(tournament.label, tournament.usage, tournament.analysis_params, archetype)
        end
      end
      unplayed_line(unplayed_count)
    end

    def unplayed_line(count)
      return unless count.positive?

      li(class: "card-usage-unplayed") do
        "#{count} other #{'tournament'.pluralize(count)} here: not played."
      end
    end

    # The link to the analysis the node reproduces trails the figures rather than wrapping the name:
    # inside a <summary>, a linked name takes the tap that was meant to open the node — measured in
    # the mobile system test (500px, Chrome's floor), where the summary's centre lands on the name and the click navigated
    # away instead of expanding. "Other formats" has no analysis to link to.
    #
    # `scope` names a sample the line's name does not: under All formats an archetype's first line
    # blends every rotation, which the analysis only shows under "All formats"; under a pool it is
    # that pool's figure.
    def node_line(name, usage, params, archetype, scope: nil)
      span(class: "card-usage-name") { name }
      span(class: "card-usage-figures") { [ scope, figures(usage) ].compact.join(" · ") }
      return unless params

      a(href: "#{analysis_base(archetype)}?#{params.to_query}", class: "card-usage-link") { "Analysis" }
    end

    # One route generation per archetype rather than per node: the widest card renders 1383 nodes
    # under 82 archetypes, and a URL helper call per node was most of the section's render time.
    # `to_query` sorts its keys (pool, tournament, venue), which is also the order the nodes build
    # them in, so the href is the one `analysis_archetype_path(archetype, **params)` would emit.
    def analysis_base(archetype)
      (@analysis_bases ||= {})[archetype.id] ||= analysis_archetype_path(archetype)
    end

    def figures(usage)
      lists = "#{usage.playing_count} of #{usage.lists_count} #{'list'.pluralize(usage.lists_count)}"
      return "not played · #{lists}" unless usage.played?

      "#{format_pct(usage.pct)}% · #{lists} · #{copies_text(usage)}"
    end

    # Archetypes::NameGroupRow's spelling — "100%", "33.3%" — so one figure reads the same on both
    # pages.
    def format_pct(pct)
      pct == pct.round ? pct.round.to_s : Kernel.format("%.1f", pct)
    end
  end
end
