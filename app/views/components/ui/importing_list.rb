# frozen_string_literal: true

module Ui
  class ImportingList < ApplicationComponent
    def initialize(pending_imports: [], item_id_prefix: "importing", list_target: nil, extra_data: {})
      @pending_imports = pending_imports
      @item_id_prefix = item_id_prefix
      @list_target = list_target
      @extra_data = extra_data
    end

    def view_template
      visible = @pending_imports.any?
      div(class: "importing-section", style: (visible ? nil : "display: none;"), data: { controller: "importing-list" }) do
        h3 { "Importing\u2026" }
        ul(
          id: "importing-decks",
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
