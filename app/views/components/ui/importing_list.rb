# frozen_string_literal: true

module Ui
  class ImportingList < ApplicationComponent
    # list_id, because the id is a DOM id and two lists on one page must not share one: the
    # event page renders a standings list beside the deck grid's own vocabulary.
    def initialize(pending_imports: [], item_id_prefix: "importing", list_target: nil,
                   extra_data: {}, list_id: "importing-decks")
      @pending_imports = pending_imports
      @item_id_prefix = item_id_prefix
      @list_target = list_target
      @extra_data = extra_data
      @list_id = list_id
    end

    def view_template
      visible = @pending_imports.any?
      div(class: "importing-section", style: (visible ? nil : "display: none;"), data: { controller: "importing-list" }) do
        h3 { "Importing\u2026" }
        ul(
          id: @list_id,
          data: { importing_list_target: "list", **@extra_data },
          class: "importing-list"
        ) do
          @pending_imports.each do |imp|
            li(id: "#{@item_id_prefix}-#{imp.id}", class: "importing-item") do
              span(class: "importing-spinner")
              plain " #{imp.label}"
            end
          end
        end
      end
    end
  end
end
