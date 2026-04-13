module Ui
  class AdminActions < ApplicationComponent
    def initialize(edit_path:, delete_path:, confirm_message:)
      @edit_path = edit_path
      @delete_path = delete_path
      @confirm_message = confirm_message
    end

    def view_template
      link_to "Edit", @edit_path, class: "btn btn-secondary btn-sm"
      plain " "
      link_to "Delete", @delete_path,
        data: { turbo_method: :delete, turbo_confirm: @confirm_message },
        class: "btn-danger btn-sm"
    end
  end
end
