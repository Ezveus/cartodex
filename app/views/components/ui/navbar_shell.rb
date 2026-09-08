module Ui
  # The navbar's chrome, shared by the signed-in and public variants. Extracted rather than
  # duplicated because it is load-bearing for the test suite, not just for looks: below 768px
  # `.navbar-menu` is display:none until the `navbar` controller adds `.navbar-menu--open`,
  # and `click_nav_link` drives exactly that. A variant missing the toggle fails every mobile
  # system test that navigates, and looks like a Capybara visibility bug.
  #
  # All three navbars go through it now, the admin one included: it was the only one still
  # carrying its own copy of this markup, so it was also the only one that would not have
  # picked up a future toggle or aria fix made here. test/system/admin_navigation_test.rb is
  # the coverage that made moving it safe.
  class NavbarShell < ApplicationComponent
    def initialize(brand_path:, brand_label: "Cartodex", brand_active: false, nav_class: nil, search: true)
      @brand_path = brand_path
      @brand_label = brand_label
      @brand_active = brand_active
      @nav_class = nav_class
      @search = search
    end

    def view_template(&block)
      nav(class: [ "navbar", @nav_class ].compact.join(" "), data: { controller: "navbar" }) do
        div(class: "navbar-inner") do
          brand
          # Deliberately outside .navbar-menu: below 768px the menu is display:none until the
          # hamburger opens it, and a search you have to unfold a menu to reach is not reachable
          # "from any page". CSS, not DOM order, puts it right of the links above the breakpoint.
          render Ui::SearchTrigger.new if @search
          button(
            class: "navbar-toggle",
            # `expanded: "false"` is the initial state only; the controller rewrites it on every
            # toggle. It used to be the *permanent* state, which is issue #105 — a screen reader was
            # told the menu was shut for as long as it was open.
            data: { action: "navbar#toggle", navbar_target: "toggle" },
            aria: { label: "Menu", expanded: "false" }
          ) { span(class: "navbar-toggle-icon") }
          div(class: "navbar-menu", data: { navbar_target: "menu" }, &block)
        end
      end
    end

    private

    # The brand is the app's Dashboard link in all three navbars, and since the grouped navbar
    # dropped "Dashboard" as an entry of its own it is the *only* thing pointing there — so it
    # takes the active class on the page it reaches, the same way any other entry does.
    # `brand_active` rather than a section read here: the shell is the one navbar component that
    # does not know what a section is, and each navbar resolves its own home ("home" for the two
    # app ones, "dashboard" for the admin panel).
    def brand
      link_to @brand_path, class: [ "navbar-brand", ("active" if @brand_active) ].compact.join(" ") do
        render Ui::Logo.new
        span(class: "navbar-brand-word") { @brand_label }
      end
    end
  end
end
