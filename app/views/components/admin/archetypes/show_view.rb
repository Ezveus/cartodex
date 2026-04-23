module Admin
  module Archetypes
    class ShowView < ApplicationComponent
      def initialize(archetype:)
        @archetype = archetype
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: @archetype.name) do
            div(class: "admin-header-actions") do
              link_to "Edit", edit_admin_archetype_path(@archetype), class: "btn btn-secondary"
              link_to "Delete", admin_archetype_path(@archetype),
                data: { turbo_method: :delete, turbo_confirm: "Delete #{@archetype.name}?" },
                class: "btn-danger"
              link_to "Back", admin_archetypes_path, class: "btn btn-secondary"
            end
          end

          table(class: "detail-table") do
            tbody do
              info_row("Primary Pokémon", @archetype.primary_pokemon.name)
              info_row("Secondary Pokémon", @archetype.secondary_pokemon&.name || "\u2014")
              info_row("Parent", @archetype.parent&.name || "\u2014")
              info_row("Results", @archetype.deck_results.count.to_s)
            end
          end

          if @archetype.children.any?
            h2 { "Sub-archetypes" }
            render Ui::DataTable.new(columns: %w[Name Primary Secondary]) do |t|
              @archetype.children.includes(:primary_pokemon, :secondary_pokemon).each do |child|
                t.row do
                  t.cell { link_to child.name, admin_archetype_path(child) }
                  t.cell { child.primary_pokemon.name }
                  t.cell { child.secondary_pokemon&.name || "\u2014" }
                end
              end
            end
          end
        end
      end

      private

      def info_row(label, value)
        tr do
          td { strong { label } }
          td { value }
        end
      end
    end
  end
end
