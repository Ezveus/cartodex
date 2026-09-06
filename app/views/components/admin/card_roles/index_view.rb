module Admin
  module CardRoles
    # The curation screen: one row per fingerprint, one checkbox per role.
    class IndexView < ApplicationComponent
      include Phlex::Rails::Helpers::TurboFrameTag

      # The rows, the pager and the empty state live inside this frame; the filter bar sits
      # outside it. Without one, the 300 ms debounce navigates the whole page and the caret is
      # gone after every keystroke — on the screen whose filter is the thing that turns 3023
      # fingerprints into 94, which is an evening's work against a month's. The three other
      # filtered listings in the app already do exactly this.
      FRAME_ID = "card_role_rows".freeze

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

          filter_bar
          scope_note
          turbo_frame_tag(FRAME_ID) do
            table
            # Inside the frame, so Turbo swaps the rows rather than the page — which leaves the
            # address bar behind, and `turbo_action: "replace"` is what puts ?page= back into it.
            render Ui::Pagination.new(page: @page, pages: @pages, turbo_action: "replace",
                                      href: ->(page) { page_href(page) })
          end
        end
      end

      private

      def filter_bar
        form_with(url: admin_card_roles_path, method: :get, class: "deck-filters",
                  data: { controller: "card-filter", turbo_frame: FRAME_ID, turbo_action: "replace" }) do
          label(class: "card-role-filter") do
            span { "Name" }
            input(type: "search", name: "q", value: @filters[:q], class: "form-input",
                  placeholder: "Card name",
                  data: { action: "input->card-filter#debounce" })
          end

          label(class: "card-role-filter") do
            span { "Card type" }
            render Ui::FilterSelect.new(name: "card_type", options: card_type_options,
                                        selected: @filters[:card_type])
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
        render Ui::DataTable.new(columns: [ "Card", "Type", *@roles.map(&:name), "Decision" ]) do
          @unfingerprinted.each do |card|
            render Row.new(card: card, roles: @roles, assignments: @assignments, writable: false)
          end

          @rows.each { |card| render Row.new(card: card, roles: @roles, assignments: @assignments) }
        end
      end

      def card_type_options
        [ [ "Any", "" ] ] + Card::CARD_TYPES.map { |type| [ type, type ] }
      end

      def page_href(page)
        admin_card_roles_path(@filters.merge(page: page))
      end
    end
  end
end
