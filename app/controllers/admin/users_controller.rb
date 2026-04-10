module Admin
  class UsersController < BaseController
    def index
      @users = User.order(:email)
    end

    def toggle_admin
      user = User.find(params[:id])
      if user == current_user
        redirect_to admin_users_path, alert: "Cannot change your own admin status."
      else
        user.update!(admin: !user.admin?)
        redirect_to admin_users_path, notice: "#{user.email} is now #{user.admin? ? 'an admin' : 'a regular user'}."
      end
    end
  end
end
