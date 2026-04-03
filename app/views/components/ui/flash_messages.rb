module Ui
  class FlashMessages < ApplicationComponent
    def view_template
      if flash[:notice]
        div(class: "flash flash-notice") { flash[:notice] }
      end

      if flash[:alert]
        div(class: "flash flash-alert") { flash[:alert] }
      end
    end
  end
end
