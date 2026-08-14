module Ui
  class AdminActions < ApplicationComponent
    # frame: the Turbo Frame both actions should target, for call sites that render
    # this component inside a frame these links must escape (pass "_top"). Left nil
    # the links carry no data-turbo-frame at all, which is what every call site
    # outside a frame wants.
    def initialize(edit_path:, delete_path:, confirm_message:, frame: nil)
      @edit_path = edit_path
      @delete_path = delete_path
      @confirm_message = confirm_message
      @frame = frame
    end

    def view_template
      link_to "Edit", @edit_path, class: "btn btn-secondary btn-sm", data: { turbo_frame: @frame }
      plain " "
      link_to "Delete", @delete_path,
        data: { turbo_method: :delete, turbo_confirm: @confirm_message, turbo_frame: @frame },
        class: "btn-danger btn-sm"
    end
  end
end
