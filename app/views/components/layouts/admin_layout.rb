module Layouts
  class AdminLayout < ApplicationComponent
    include Phlex::Rails::Layout

    def view_template(&block)
      doctype
      html do
        head do
          title { helpers.content_for(:title) || "Cartodex Admin" }
          meta(name: "viewport", content: "width=device-width,initial-scale=1")
          csrf_meta_tags
          csp_meta_tag
          stylesheet_link_tag :app, data_turbo_track: "reload"
          javascript_importmap_tags
        end
        body do
          render Ui::Navbar.new(
            variant: :admin,
            current_user: helpers.current_user,
            active_controller: helpers.controller_name
          )
          turbo_stream_from(helpers.current_user, :notifications)
          render Ui::FlashMessages.new
          yield
        end
      end
    end
  end
end
