module Admin
  module Archetypes
    class IndexView < ApplicationComponent
      def initialize(archetypes:)
        @archetypes = archetypes
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Archetypes") do
            link_to "New Archetype", helpers.new_admin_archetype_path, class: "btn btn-primary"
          end

          render Ui::AdminTable.new(columns: %w[Name Primary Secondary Parent Children Actions]) do
            @archetypes.each do |arch|
              tr do
                td { link_to arch.name, helpers.admin_archetype_path(arch) }
                td { arch.primary_pokemon.name }
                td { arch.secondary_pokemon&.name || "\u2014" }
                td { arch.parent ? link_to(arch.parent.name, helpers.admin_archetype_path(arch.parent)) : "\u2014" }
                td { arch.children.size.to_s }
                td do
                  link_to "Edit", helpers.edit_admin_archetype_path(arch), class: "btn btn-secondary btn-sm"
                  plain " "
                  link_to "Delete", helpers.admin_archetype_path(arch),
                    data: { turbo_method: :delete, turbo_confirm: "Delete #{arch.name}?" },
                    class: "btn-danger btn-sm"
                end
              end
            end
          end
        end
      end
    end
  end
end
