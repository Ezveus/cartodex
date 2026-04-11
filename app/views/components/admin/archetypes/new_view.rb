module Admin
  module Archetypes
    class NewView < ApplicationComponent
      def initialize(archetype:)
        @archetype = archetype
      end

      def view_template
        div(class: "admin-container") do
          h1 { "New Archetype" }
          render Admin::Archetypes::Form.new(archetype: @archetype)
        end
      end
    end
  end
end
