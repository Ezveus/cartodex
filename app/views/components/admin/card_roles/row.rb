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
    #
    # Which is why "Clear" is a *second* form, rendered as a hidden sibling with the row's own
    # button pointing at it through HTML5's `form` attribute: forms cannot nest, and the two
    # actions genuinely differ — one records a decision, the other withdraws every decision made
    # about this card and hands it back to the suggester.
    #
    # The two of them sit in a wrapper that carries the DOM id, because the Turbo Stream replaces
    # *one* element: with the id on the row's own form, each save inserted a fresh clear form
    # beside the one already there — measured, two after two saves, both carrying the same id.
    class Row < ApplicationComponent
      # A card with no fingerprint cannot be labelled: an assignment would name a key no card
      # carries and the report could never join it. The row renders, and says so, with its boxes
      # disabled — a click that could not be written must not be offered.
      def initialize(card:, roles:, assignments:, writable: true)
        # The fingerprint is the card's own: rows_for picks its representative *within* a
        # fingerprint group, and #update looks the card up *by* the fingerprint, so a second
        # keyword could only ever disagree with this one.
        @fingerprint = card.fingerprint
        @card = card
        @roles = roles
        @assignments = assignments
        @writable = writable
      end

      def self.dom_id(fingerprint) = "card-role-#{fingerprint}"

      def view_template
        unless @writable
          return div(id: "card-role-unfingerprinted-#{@card.id}", class: "data-table-row") { cells }
        end

        div(id: self.class.dom_id(@fingerprint), class: "card-role-row") do
          form_with(url: admin_card_role_path(@fingerprint), method: :patch,
                    class: "data-table-row", data: { controller: "card-filter" }) { cells }
          clear_form if decided?
        end
      end

      private

      def cells
        div(class: "data-table-cell", data: { label: "Card" }) { card_cell }
        div(class: "data-table-cell", data: { label: "Type" }) { type_label }
        @roles.each { |role| role_cell(role) }
        div(class: "data-table-cell", data: { label: "Decision" }) { actions }
      end

      # Why a Save button exists at all: agreeing with what the rules proposed is the commonest
      # answer on this screen, and with `change` as the only trigger there was nothing to click
      # for it — confirming a row meant ticking a role that is wrong, publishing it, and unticking
      # it again.
      def actions
        return span(class: "card-role-note") { "not labellable" } unless @writable

        input(type: "submit", value: "Save", class: "btn btn-secondary btn-sm")
        return unless decided?

        button(type: "submit", form: clear_form_id, class: "btn btn-secondary btn-sm") { "Clear" }
      end

      # Hidden, and only ever submitted by the button above through its `form` attribute: a DELETE
      # needs a form of its own and it cannot sit inside the row's.
      def clear_form
        button_to("Clear decisions", admin_card_role_path(@fingerprint), method: :delete,
                  class: "card-role-clear-submit",
                  form: { id: clear_form_id, class: "card-role-clear-form",
                          data: { turbo_confirm: "Forget every decision recorded for " \
                                                 "#{@card.name}? The rules may propose roles for " \
                                                 "it again." } })
      end

      def clear_form_id = "card-role-clear-#{@fingerprint}"

      # Anything a human has said about this card, yes or no. Only then is there something to
      # clear.
      def decided?
        @roles.any? { |role| @assignments[[ @fingerprint, role.id ]]&.source == "curated" }
      end

      # The wrapper is load-bearing, and only a browser shows why: below 768px `.data-table` turns
      # each row into a card whose cells are `display: flex`, so a name and a note placed directly
      # in the cell become two flex items on one line — the same defect measured on the archetype
      # catalog, where a note took a third of the cell and doubled the row's height. Inside a
      # column wrapper they are one item and they stack.
      def card_cell
        div(class: "card-role-card") do
          span(class: "card-role-name") { @card.printing_label }
          span(class: "card-role-note") { "no fingerprint — cannot be labelled" } unless @writable
        end
      end

      def type_label
        [ @card.card_type, @card.subtype.presence ].compact.join(" · ")
      end

      # Three states, not two, and the third is the one this screen exists for: a role a rule
      # proposed, a role a human decided (yes *or* no), and a role nobody has looked at. A refusal
      # renders as an unticked box exactly like an untouched one, so without the `--decided`
      # modifier an admin working through 3023 fingerprints cannot see what they have already done.
      def role_cell(role)
        assignment = @assignments[[ @fingerprint, role.id ]]

        div(class: "data-table-cell", data: { label: role.name }) do
          label(class: cell_class(assignment), title: title_for(role, assignment)) do
            input(**checkbox_attributes(role, assignment))
            span(class: "card-role-choice-name") { role.name }
          end
        end
      end

      def title_for(role, assignment)
        case assignment&.source
        when "suggested" then "#{role.description} — proposed by the rules; saving this row decides it."
        when "curated" then "#{role.description} — decided by hand."
        else role.description
        end
      end

      def cell_class(assignment)
        [ "card-role-choice", state_modifier(assignment) ].compact.join(" ")
      end

      def state_modifier(assignment)
        case assignment&.source
        when "suggested" then "card-role-choice--suggested"
        when "curated" then "card-role-choice--decided"
        end
      end

      # `aria_label`, not the visible span alone: that span is `display: none` above the
      # breakpoint (the column heading names the role there), and a hidden label leaves the
      # checkbox with no accessible name — seven anonymous boxes per row to a screen reader.
      def checkbox_attributes(role, assignment)
        attributes = {
          type: "checkbox", name: "roles[]", value: role.slug,
          class: "card-role-checkbox", aria_label: "#{role.name} — #{@card.name}"
        }
        attributes[:checked] = true if assignment && !assignment.rejected
        # The row submits itself on any change, so the state shown is always one the server wrote.
        @writable ? attributes.merge(data: { action: "change->card-filter#submit" }) : attributes.merge(disabled: true)
      end
    end
  end
end
