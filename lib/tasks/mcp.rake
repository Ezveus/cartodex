namespace :mcp do
  desc "Rotate a user's MCP API token and print the new raw value (shown once, not retrievable later). Usage: bin/rails 'mcp:token[email@example.com]'"
  task :token, [ :email ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    raw = user.regenerate_api_token
    puts raw
  end
end
