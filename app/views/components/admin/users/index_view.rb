module Admin
  module Users
    class IndexView < ApplicationComponent
      def initialize(users:, current_user:)
        @users = users
        @current_user = current_user
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Users" }

          render Ui::AdminTable.new(columns: %w[Email Admin Decks Joined Actions]) do
            @users.each do |user|
              tr do
                td { user.email }
                td { user.admin? ? "Yes" : "No" }
                td { user.decks.size.to_s }
                td { user.created_at.strftime("%Y-%m-%d") }
                td do
                  if user != @current_user
                    link_to(
                      user.admin? ? "Remove admin" : "Make admin",
                      helpers.toggle_admin_admin_user_path(user),
                      data: {
                        turbo_method: :patch,
                        turbo_confirm: "#{user.admin? ? 'Remove' : 'Grant'} admin for #{user.email}?"
                      },
                      class: "btn btn-secondary btn-sm"
                    )
                  else
                    span(class: "text-muted") { "You" }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
