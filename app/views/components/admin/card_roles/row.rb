module Admin
  module CardRoles
    # One card's roles, and the whole row is the form.
    #
    # It is its own component because a write re-renders exactly it, through a Turbo Stream — the
    # same reason Tournaments::Standings::Row is one. What the reader then sees is the row the
    # database holds rather than the box the browser ticked, which matters here more than usual:
    # a tick, a promotion of a suggestion and a refusal all look identical in the DOM until the
    # server answers.
    #
    # The <form> *is* the `.data-table-row`, rather than sitting inside one: that class is a flex
    # container of `.data-table-cell` children, so a form wrapped around the cells would become
    # the row's single flex child and collapse the layout — and below 768px, where each row
    # becomes a card and each cell grows a `::before` label, it would take the labels with it.
    class Row < ApplicationComponent
      # A card with no fingerprint cannot be labelled: an assignment would name a key no card
      # carries and the report could never join it. The row renders, and says so, with its boxes
      # disabled — a click that could not be written must not be offered.
      def initialize(fingerprint:, card:, roles:, assignments:, writable: true)
        @fingerprint = fingerprint
        @card = card
        @roles = roles
        @assignments = assignments
        @writable = writable
      end

      def self.dom_id(fingerprint) = "card-role-#{fingerprint}"

      def view_template
        if @writable
          form_with(url: admin_card_role_path(@fingerprint), method: :patch,
                    id: self.class.dom_id(@fingerprint), class: "data-table-row",
                    data: { controller: "card-filter" }) { cells }
        else
          div(id: "card-role-unfingerprinted-#{@card.id}", class: "data-table-row") { cells }
        end
      end

      private

      def cells
        div(class: "data-table-cell", data: { label: "Card" }) { card_cell }
        div(class: "data-table-cell", data: { label: "Type" }) { type_label }
        @roles.each { |role| role_cell(role) }
      end

      def card_cell
        span(class: "card-role-name") { @card.printing_label }
        span(class: "card-role-note") { "no fingerprint — cannot be labelled" } unless @writable
      end

      def type_label
        [ @card.card_type, @card.subtype.presence ].compact.join(" · ")
      end

      # A suggestion is pre-ticked but styled apart from a decision, because the difference is the
      # only thing this screen exists to record: a ticked box the rules proposed is "nobody has
      # said yes yet", and saving the row is what turns it into one.
      def role_cell(role)
        assignment = @assignments[[ @fingerprint, role.id ]]
        suggested = assignment&.source == "suggested"

        div(class: "data-table-cell", data: { label: role.name }) do
          label(class: cell_class(suggested), title: role.description) do
            input(**checkbox_attributes(role, assignment))
            span { role.name }
          end
        end
      end

      def cell_class(suggested)
        suggested ? "card-role-choice card-role-choice--suggested" : "card-role-choice"
      end

      def checkbox_attributes(role, assignment)
        attributes = {
          type: "checkbox", name: "roles[]", value: role.slug,
          class: "card-role-checkbox"
        }
        attributes[:checked] = true if assignment && !assignment.rejected
        # The row submits itself on any change, so the state shown is always one the server wrote.
        @writable ? attributes.merge(data: { action: "change->card-filter#submit" }) : attributes.merge(disabled: true)
      end
    end
  end
end
