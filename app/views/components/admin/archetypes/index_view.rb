module Admin
  module Archetypes
    class IndexView < ApplicationComponent
      def initialize(archetypes:)
        @archetypes = archetypes
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Archetypes") do
            link_to "New Archetype", new_admin_archetype_path, class: "btn btn-primary"
          end

          render Ui::DataTable.new(columns: %w[Name Primary Secondary Parent Children Actions]) do |t|
            @archetypes.each do |arch|
              t.row do
                t.cell { link_to arch.name, admin_archetype_path(arch) }
                t.cell { arch.primary_pokemon.name }
                t.cell { arch.secondary_pokemon&.name || "\u2014" }
                t.cell { arch.parent ? link_to(arch.parent.name, admin_archetype_path(arch.parent)) : "\u2014" }
                t.cell { arch.children.size.to_s }
                t.cell { render Ui::AdminActions.new(edit_path: edit_admin_archetype_path(arch), delete_path: admin_archetype_path(arch), confirm_message: "Delete #{arch.name}?") }
              end
            end
          end
        end
      end
    end
  end
end
