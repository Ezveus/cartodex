module Layouts
  class ApplicationLayout < ApplicationComponent
    include Phlex::Rails::Layout

    def view_template(&block)
      doctype
      html do
        head do
          title { helpers.content_for(:title) || "Cartodex" }
          meta(name: "viewport", content: "width=device-width,initial-scale=1")
          meta(name: "apple-mobile-web-app-capable", content: "yes")
          meta(name: "mobile-web-app-capable", content: "yes")
          csrf_meta_tags
          csp_meta_tag
          yield(:head)
          link(rel: "icon", href: "/icon.png", type: "image/png")
          link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
          link(rel: "apple-touch-icon", href: "/icon.png")
          stylesheet_link_tag :app, data_turbo_track: "reload"
          javascript_importmap_tags
        end
        body do
          if helpers.user_signed_in?
            turbo_stream_from(helpers.current_user, :notifications)
            render Ui::AppNavbar.new(
              current_user: helpers.current_user,
              active_controller: helpers.controller_name
            )
          end
          render Ui::FlashMessages.new
          yield
        end
      end
    end
  end
end
