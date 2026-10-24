module Decks
  # A deck page's list: Decks::Layout's sections in page order, a group's children inside it, each
  # row drawn by the component `row` returns for it — the owner's rows or the public ones, which
  # is the one thing the two pages do not share.
  class DeckSections < ApplicationComponent
    def initialize(sections:, row:, **attributes)
      @sections = sections
      @row = row
      @attributes = attributes
    end

    def view_template
      children = @sections.select(&:parent_key).group_by(&:parent_key)

      div(class: "deck-sections", **@attributes) do
        @sections.reject(&:parent_key).each { |section| render_section(section, children) }
      end
    end

    private

    def render_section(section, children)
      render DeckSection.new(section: section) do
        if section.kind == :group
          children.fetch(section.key, []).each { |child| render_section(child, children) }
        else
          section.rows.each { |row| render @row.call(row) }
        end
      end
    end
  end
end
