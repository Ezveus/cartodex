module Ui
  # nav_link, shared by the three navbars. A module rather than a method on Ui::NavbarShell:
  # the shell takes its links as a block, and a block is evaluated in the *caller's* context,
  # so a method defined on the shell is unreachable from inside it.
  #
  # What it centralises is the active-class rule, which reads @active_controller — the
  # including component's own ivar, set from `controller_name`. That is also why the known
  # dual-highlight is a property of the rule and not of one navbar: "Decks" and "Shared decks"
  # both light up on /decks/shared, whose controller_name is "decks".
  module NavLinks
    private

    def nav_link(label, path, controller)
      link_to label, path, class: [ "navbar-link", ("active" if @active_controller == controller) ].compact.join(" ")
    end
  end
end
