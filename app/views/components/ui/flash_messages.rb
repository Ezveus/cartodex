module Ui
  class FlashMessages < ApplicationComponent
    def view_template
      div(id: "flash-messages") do
        if flash[:notice]
          div(class: "flash flash-notice", data: { controller: "flash" }) { flash[:notice] }
        end

        if flash[:alert]
          div(class: "flash flash-alert", data: { controller: "flash" }) { flash[:alert] }
        end
      end
    end
  end
end
