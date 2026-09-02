module Ui
  # The navbar's chrome, shared by the signed-in and public variants. Extracted rather than
  # duplicated because it is load-bearing for the test suite, not just for looks: below 768px
  # `.navbar-menu` is display:none until the `navbar` controller adds `.navbar-menu--open`,
  # and `click_nav_link` drives exactly that. A variant missing the toggle fails every mobile
  # system test that navigates, and looks like a Capybara visibility bug.
  class NavbarShell < ApplicationComponent
    def initialize(brand_path:)
      @brand_path = brand_path
    end

    def view_template(&block)
      nav(class: "navbar", data: { controller: "navbar" }) do
        div(class: "navbar-inner") do
          link_to "Cartodex", @brand_path, class: "navbar-brand"
          button(
            class: "navbar-toggle",
            data: { action: "navbar#toggle" },
            aria: { label: "Menu", expanded: "false" }
          ) { span(class: "navbar-toggle-icon") }
          div(class: "navbar-menu", data: { navbar_target: "menu" }, &block)
        end
      end
    end
  end
end
