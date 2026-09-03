module Ui
  # nav_link, shared by the three navbars. A module rather than a method on Ui::NavbarShell:
  # the shell takes its links as a block, and a block is evaluated in the *caller's* context,
  # so a method defined on the shell is unreachable from inside it.
  #
  # What it centralises is the active-class rule, which reads @active_section — the including
  # component's own ivar, set from `section_for` below. A request resolves to exactly **one**
  # section and a link declares the sections that light it, which is what makes "one entry is
  # lit" structural rather than a coincidence of two independent rules: "Decks" and "Shared
  # decks" both used to light up on every DecksController page, since the rule keyed on
  # `controller_name` and both of them named it.
  module NavLinks
    # The nav section a request belongs to. The controller name is the section for every route
    # in the app but one: DecksController serves both deck lists, so /decks/shared is told
    # apart from the rest of the controller by its action. A deck's own page stays in "decks" —
    # the section says which list the page hangs off, and the visitor's navbar, which has no
    # "Decks" entry, is served instead by its "Shared decks" link declaring both sections.
    def self.section_for(controller_name, action_name)
      return "shared_decks" if controller_name == "decks" && action_name == "shared"

      controller_name
    end

    private

    def nav_link(label, path, *sections)
      active = sections.include?(@active_section)
      link_to label, path, class: [ "navbar-link", ("active" if active) ].compact.join(" ")
    end
  end
end
