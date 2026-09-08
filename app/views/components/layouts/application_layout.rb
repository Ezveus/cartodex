module Layouts
  class ApplicationLayout < ApplicationComponent
    include Phlex::Rails::Layout

    def view_template(&block)
      doctype
      html do
        head do
          title { content_for(:title) || "Cartodex" }
          meta(name: "viewport", content: "width=device-width,initial-scale=1")
          meta(name: "robots", content: "noindex, nofollow")
          meta(name: "apple-mobile-web-app-capable", content: "yes")
          meta(name: "mobile-web-app-capable", content: "yes")
          # Rendered on every page, never conditionally: OgPreviewHost#og_preview answers the site
          # payload unless the action assigned its own, so a page nobody thought about still
          # previews as Cartodex rather than as a bare URL. `noindex` above and these tags are not
          # in tension — one is about search indexing, the other about a link pasted into a chat,
          # and the crawler that unfurls a link is not the crawler that indexes one.
          render Ui::OgTags.new(payload: og_preview)
          csrf_meta_tags
          csp_meta_tag
          yield(:head)
          # `sizes` is what lets a browser pick, and the 16 and 32 are a *different drawing* — the
          # mark without its five bench slots, which collapse into indistinguishable pips below
          # roughly 48px. icon.svg stays last so a browser that understands SVG prefers it at the
          # large sizes where the full mark reads.
          link(rel: "icon", href: "/icon-16.png", sizes: "16x16", type: "image/png")
          link(rel: "icon", href: "/icon-32.png", sizes: "32x32", type: "image/png")
          link(rel: "icon", href: "/icon-192.png", sizes: "192x192", type: "image/png")
          link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
          link(rel: "apple-touch-icon", href: "/icon-512.png")
          stylesheet_link_tag :app, data_turbo_track: "reload"
          javascript_importmap_tags
        end
        # The search-overlay controller sits on <body> rather than on a wrapper of its own: its
        # trigger is in the navbar and its field is either in the dialog below or somewhere in the
        # page, and a Stimulus action only resolves to a controller on an ancestor.
        # turbo:before-cache closes the dialog before the snapshot is taken. The overlay's usual
        # exit is a result that navigates away, so the page left behind would otherwise be cached
        # with the dialog open — and restored, an open <dialog> is no longer modal: no backdrop to
        # click, and open() sees it as already open, so nothing can dismiss it.
        body(data: {
          controller: "search-overlay",
          action: "keydown@document->search-overlay#shortcut " \
                  "turbo:before-cache@document->search-overlay#close"
        }) do
          if user_signed_in?
            turbo_stream_from(current_user, :notifications)
            render Ui::AppNavbar.new(current_user: current_user, active_section: active_section)
          else
            render Ui::PublicNavbar.new(active_section: active_section)
          end
          render Search::Overlay.new if search_overlay?
          render Ui::FlashMessages.new
          yield
        end
      end
    end

    private

    def active_section
      Ui::NavLinks.section_for(controller_name, action_name)
    end
  end
end
