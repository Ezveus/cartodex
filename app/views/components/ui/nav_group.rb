# frozen_string_literal: true

module Ui
  # One expanding entry of a navbar: a trigger, and a panel of links under it.
  #
  # **Entries arrive as data, not as a block, and that is the load-bearing decision.** The group
  # lights when the request's section is in the union of its entries' sections, and that union is
  # computed from the entries themselves — so a link added to a group can never be forgotten by the
  # group's own list, because there is no second list. A `sections:` keyword beside a block of
  # links would be exactly that second list, and the first entry added to a group would drift out
  # of it silently. This is the same property Ui::NavLinks.section_for gives the flat links: "one
  # entry is lit, and it is the right one" holds by construction rather than by two rules agreeing.
  #
  # It renders **three** children, and the second one is why no JavaScript here knows about the
  # breakpoint:
  #
  #   - a <button> trigger, `display: none` below 768px;
  #   - a <span> heading carrying the same label, `display: none` above it;
  #   - the panel, absolutely positioned above the breakpoint and a plain block below it, where the
  #     drawer shows every group already open.
  #
  # One element restyled by a media query was the obvious alternative and is wrong twice: it puts
  # the breakpoint in a third place (the CSS, card_preview_controller.js, and a matchMedia here),
  # and it leaves a button announcing `aria-expanded="false"` over a panel the drawer is showing.
  #
  # Links are written by hand rather than with `link_to` — the paths arrive as strings, so nothing
  # here needs a route helper, and the component then renders outside a request context. That is
  # the same reason Ui::ArchetypeBadge writes its own anchor.
  class NavGroup < ApplicationComponent
    def initialize(label:, id:, entries: [], active_section: nil, initial: nil, align: :left)
      @label = label
      @id = id
      @entries = entries
      @active_section = active_section
      @initial = initial
      @align = align
    end

    def view_template(&block)
      div(
        class: "navbar-group",
        data: {
          controller: "dropdown",
          # The generic controller defaults to the class the two deck dropdowns are hidden by; the
          # navbar's panel has its own, because it is a dark panel on a dark bar rather than the
          # white card .dropdown-menu draws.
          dropdown_open_class_value: "navbar-group-panel--open"
          # No `data-action` for Escape or turbo:before-cache: the controller registers both as
          # document listeners itself, so every caller gets them. A close path wired up in markup
          # is a close path the two deck dropdowns would not have.
        }
      ) do
        trigger
        span(class: "navbar-group-heading", aria_hidden: "true") { @label }
        panel(&block)
      end
    end

    private

    def trigger
      button(
        type: "button",
        class: [ "navbar-group-trigger", ("active" if active?) ].compact.join(" "),
        aria: { expanded: "false", controls: dom_id, label: (@label if @initial) }.compact,
        data: { action: "dropdown#toggle", dropdown_target: "trigger" }
      ) do
        if @initial
          span(class: "navbar-group-initial", aria_hidden: "true") { @initial }
        else
          plain @label
        end
        span(class: "navbar-group-caret", aria_hidden: "true")
      end
    end

    def panel(&block)
      div(
        class: [ "navbar-group-panel", ("navbar-group-panel--right" if @align == :right) ].compact.join(" "),
        id: dom_id,
        data: { dropdown_target: "menu" }
      ) do
        @entries.each { |label, path, sections| entry(label, path, sections) }
        # Passed `self` so a caller outside a Phlex render — a component test — can write into the
        # panel; a caller inside one ignores the argument and writes through its own buffer.
        yield(self) if block
      end
    end

    def entry(label, path, sections)
      a(
        href: path,
        class: [ "navbar-link", ("active" if sections.include?(@active_section)) ].compact.join(" ")
      ) { label }
    end

    # `@active_section` is nil on no page the app serves — section_for always answers a controller
    # name — but a caller may always pass it, and an entry naming no section (the admin navbar's
    # "Jobs" leaves the app entirely) must not be read as matching everything.
    def active?
      return false if @active_section.nil?

      @entries.any? { |_label, _path, sections| sections.include?(@active_section) }
    end

    def dom_id
      "navbar-group-#{@id}"
    end
  end
end
