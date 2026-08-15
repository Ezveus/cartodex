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
  end
end
