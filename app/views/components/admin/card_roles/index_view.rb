module Admin
  module CardRoles
    # The curation screen: one row per fingerprint, one checkbox per role.
    class IndexView < ApplicationComponent
      def initialize(rows:, unfingerprinted:, roles:, assignments:, page:, pages:, filters:)
        @rows = rows
        @unfingerprinted = unfingerprinted
        @roles = roles
        @assignments = assignments
        @page = page
        @pages = pages
        @filters = filters
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Card Roles") do
            button_to "Suggest roles", suggest_admin_card_roles_path(@filters),
              class: "btn btn-secondary"
          end

          filters
          scope_note
          table
          render Ui::Pagination.new(page: @page, pages: @pages, href: ->(page) { page_href(page) })
        end
      end

      private

      def filters
        form_with(url: admin_card_roles_path, method: :get, class: "deck-filters",
                  data: { controller: "card-filter" }) do
          label(class: "card-role-filter") do
            span { "Name" }
            input(type: "search", name: "q", value: @filters[:q], class: "form-input",
                  placeholder: "Card name",
                  data: { action: "input->card-filter#debounce" })
          end

          label(class: "card-role-filter") do
            span { "Card type" }
            select(name: "card_type", class: "form-input",
                   data: { action: "change->card-filter#submit" }) do
              option(value: "") { "Any" }
              Card::CARD_TYPES.each do |type|
                option(value: type, selected: @filters[:card_type] == type) { type }
              end
            end
          end

          label(class: "card-role-filter card-role-filter--check") do
            # The hidden field is what a bare checkbox needs: unchecked it posts nothing at all,
            # and "nothing" would read as the default, which is on — so unticking it could never
            # take effect.
            input(type: "hidden", name: "played", value: "0")
            input(type: "checkbox", name: "played", value: "1", checked: @filters[:played],
                  data: { action: "change->card-filter#submit" })
            span { "Played in a recorded list" }
          end
        end
      end

      # The default filter hides most of the catalogue, so the page says which population it is
      # showing rather than leaving a reader to infer it from a box they did not tick.
      def scope_note
        p(class: "archetype-sample-note") { scope_sentence }
      end

      def scope_sentence
        if @filters[:played]
          "Showing the cards a recorded list plays. Untick the filter to curate the whole catalogue."
        else
          "Showing the whole catalogue. Most of it is never played in a recorded list."
        end
      end

      def table
        render Ui::DataTable.new(columns: [ "Card", "Type", *@roles.map(&:name) ]) do
          @unfingerprinted.each do |card|
            render Row.new(fingerprint: card.fingerprint, card: card, roles: @roles,
                           assignments: @assignments, writable: false)
          end

          @rows.each do |row|
            render Row.new(fingerprint: row.fingerprint, card: row.card, roles: @roles,
                           assignments: @assignments)
          end
        end
      end

      def page_href(page)
        admin_card_roles_path(@filters.merge(page: page))
      end
    end
  end
end
