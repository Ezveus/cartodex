module Ui
  class FlashMessages < ApplicationComponent
    def view_template
      div(id: "flash-messages") do
        if flash[:notice]
          message(flash[:notice], "flash-notice")
        end

        if flash[:alert]
          message(flash[:alert], "flash-alert")
        end

        search_engine_announcement if user_signed_in? && current_user.search_engine_announcement_pending?
      end
    end

    private

    # role/aria-live so a screen reader announces the message: a flash is the
    # only sign that something happened, and it is often the only sign that
    # something failed. Mirrored by helpers/flash.js, which builds the same
    # markup for controllers that write through the API in the background.
    def message(text, modifier)
      div(
        class: "flash #{modifier}",
        role: "status",
        aria_live: "polite",
        data: { controller: "flash" }
      ) { text }
    end

    # Shown until the browser says it was seen (announcement_controller.js), which it does on
    # connect — so, once. Persistent, unlike the other flashes: it carries a link, and a message
    # that removes itself after five seconds takes the link with it before anyone has read the
    # sentence. Temporary in Turbo's sense: a page restored from the cache must not show it again.
    def search_engine_announcement
      div(
        class: "flash flash-info",
        role: "status",
        aria_live: "polite",
        data: {
          controller: "flash announcement",
          flash_persistent_value: "true",
          announcement_url_value: search_engine_announcement_path,
          turbo_temporary: true,
          testid: "search-engine-announcement"
        }
      ) do
        span do
          plain "New: search Cartodex straight from your browser's address bar. "
          a(href: settings_path(anchor: "search-engine")) { "Set it up in Settings" }
        end
        button(
          type: "button",
          class: "flash-close",
          aria_label: "Dismiss",
          data: { action: "flash#dismiss" }
        ) { "×" }
      end
    end
  end
end
