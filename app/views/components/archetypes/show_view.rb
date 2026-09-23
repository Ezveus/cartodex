module Archetypes
  # The front page of one archetype: its decks. The reader's own come first, then every public
  # one, most recent event first. The metagame report is one click away, on
  # Archetypes::AnalysisView — see Archetypes::DeckList for which decks belong and why.
  #
  # The pager makes full page visits and sits in no Turbo Frame, on purpose: the page has no live
  # filter for a frame to serve, and a frame-navigated action under a `rate_limit` swallows its 429
  # without a trace (the trap docs/architecture/deck-odds.md records for decks#odds).
  class ShowView < ApplicationComponent
    # `recorded` says whether the archetype has standings at all. It is only asked for when the
    # public list is empty, where it decides whether the empty state points at the analysis.
    def initialize(archetype:, list:, recorded: false)
      @archetype = archetype
      @list = list
      @recorded = recorded
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: @archetype.name) do
          div(class: "decks-header-actions") do
            render Ui::ArchetypeBadge.new(archetype: @archetype)
            link_to "Analysis", analysis_archetype_path(@archetype), class: "btn btn-primary"
            link_to "Back to Archetypes", archetypes_path, class: "btn btn-secondary"
          end
        end

        own_decks if @list.own_decks.any?
        public_decks
      end
    end

    private

    def own_decks
      section(class: "archetype-decks archetype-own-decks") do
        h2 { "Your decks" }
        grid(@list.own_decks) { |deck| deck.shared? ? "Shared" : "Private" }
      end
    end

    def public_decks
      section(class: "archetype-decks archetype-public-decks") do
        h2 { "Decks" }
        if @list.decks.any?
          p(class: "archetype-decks-count") { decks_count }
          grid(@list.decks) { |deck| @list.caption_for(deck) }
          render Ui::Pagination.new(
            page: @list.page, pages: @list.pages,
            href: ->(page) { archetype_path(@archetype, page: page) }
          )
        else
          empty_state
        end
      end
    end

    # `public_listing: true` for the reader's own decks too: the owner's badges (Physical,
    # Proxies…) read the collection and belong on /decks, and the compare checkbox needs the
    # controller only that page carries.
    def grid(decks, &caption)
      div(class: "decks-grid") do
        decks.each do |deck|
          render Decks::DeckCard.new(deck: deck, with_actions: false, public_listing: true,
                                     caption: caption.call(deck), archetype_badge: false)
        end
      end
    end

    # The reader's own shared decks are public too, but they sit in "Your decks" and not here, so
    # the bare "N public decks" would print one short for their owner while a visitor reads the
    # true number.
    def decks_count
      count = "#{@list.total} public #{'deck'.pluralize(@list.total)}"
      @list.own_decks.any?(&:shared?) ? "#{count} besides yours" : count
    end

    # The same correction as `decks_count`, on the branch it never reaches: when the reader's own
    # shared deck is the archetype's only public one, "No public deck" would sit right under it.
    def empty_state
      p(class: "empty-state") do
        plain @list.own_decks.any?(&:shared?) ? "No other public deck of this archetype yet." : "No public deck of this archetype yet."
        if @recorded
          plain " Its recorded results are in the "
          link_to "analysis", analysis_archetype_path(@archetype)
          plain "."
        end
      end
    end
  end
end
