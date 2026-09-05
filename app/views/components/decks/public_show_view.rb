module Decks
  # A shared deck, as anybody but its owner sees it: the decklist and the exports.
  #
  # A separate file rather than a flag on Decks::ShowView, which carries ten owner-only
  # affordances (inline editing, card search, result logging, allocation steppers, printing
  # pickers, the tournament PDF, the actions dropdown…). Guarding each of them would put ten
  # conditions in the app's largest component, and one forgotten condition is a collection
  # leak to a stranger. This view cannot leak what it does not contain.
  class PublicShowView < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      div(class: "deck-show-container", data: { controller: "card-preview" }) do
        header_section
        stats_section
        div(class: "deck-show-content") do
          main_section
          preview_section
        end
      end
    end

    private

    # `.deck-show-header h1` is what the image export names the file from.
    def header_section
      div(class: "deck-show-header") do
        div do
          h1 { @deck.name }
          render Decks::PublicBadges.new(deck: @deck)
          p(class: "deck-show-description") { @deck.description } if @deck.description.present?
        end
      end
      # No tournament_pdf: it reads one of the owner's tournament profiles.
      nav(class: "deck-actions-bar") { render Decks::ExportDropdown.new(deck: @deck) }
    end

    # The card count only. No wins, losses, draws or timeouts: the record stays private.
    def stats_section
      div(class: "deck-show-stats") do
        render Ui::Stat.new(value: @deck.deck_cards.sum(&:quantity), label: "cards")
      end
    end

    # The same section markup as Decks::ShowView — `.deck-section`, `.deck-section-group`,
    # `.deck-subsection` and their headings are what the stylesheet styles — so the public page
    # reads like the owner's, Trainers split by subtype included. Duplicated rather than shared:
    # ShowView's card_list is where the owner controls come from, and this file must not import
    # it. The labels are the one thing borrowed, since they are data rather than markup.
    def main_section
      div(class: "deck-show-main") do
        groups = @deck.deck_cards.group_by { |deck_card| deck_card.card.card_type }

        card_type_section("Pokémon", groups["Pokémon"]) if groups["Pokémon"].present?
        trainer_section(groups["Trainer"]) if groups["Trainer"].present?
        card_type_section("Energy", groups["Energy"]) if groups["Energy"].present?
      end
    end

    def card_type_section(type, group)
      div(class: "deck-section") do
        h2 { heading_text(type, group) }
        card_list(group)
      end
    end

    def trainer_section(group)
      div(class: "deck-section-group") do
        h2 { "Trainer" }
        # Grouped on the label, not the raw subtype, for the reason Decks::ShowView is: two
        # spellings of the tool bucket reach this table, and iterating its keys would draw two
        # sections both titled "Tool".
        labels = Decks::ShowView::TRAINER_SUBTYPE_LABELS
        subtype_groups = group.group_by { |deck_card| labels.fetch(deck_card.card.subtype.to_s, "Other") }

        labels.values.uniq.each do |label|
          subgroup = subtype_groups.delete(label)
          trainer_subtype_section(label, subgroup) if subgroup.present?
        end

        other = subtype_groups.values.flatten
        trainer_subtype_section("Other", other) if other.present?
      end
    end

    def trainer_subtype_section(label, group)
      div(class: "deck-section deck-subsection") do
        h3 { heading_text(label, group) }
        card_list(group)
      end
    end

    # Plain text where ShowView wraps the numbers in deck-totals targets: nothing on this page
    # can change a quantity, so there is nothing to keep in sync.
    def heading_text(label, group)
      "#{label} (#{group.sum(&:quantity)} — #{group.size} unique)"
    end

    def card_list(group)
      ul(class: "deck-card-list") do
        group.sort_by { |deck_card| deck_card.card.name }.each do |deck_card|
          render Decks::PublicDeckCardItem.new(deck_card: deck_card)
        end
      end
    end

    # Copied verbatim from Decks::ShowView, targets included. Above the 768px breakpoint the
    # hover pane is what fills; below it, card_preview_controller.js checks
    # window.innerWidth <= 768 and uses the <dialog> instead — so both halves have to be here
    # or the mobile side of the preview silently does nothing.
    def preview_section
      render Ui::CardPreview.new(wrapper_class: "deck-show-preview")
      render Ui::CardPreviewModal.new
    end
  end
end
