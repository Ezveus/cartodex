namespace :mcp do
  desc "Print a user's MCP API token. Set REGENERATE=1 to rotate it. Usage: bin/rails 'mcp:token[email@example.com]'"
  task :token, [ :email ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    user.regenerate_api_token if ENV["REGENERATE"] == "1"
    puts user.api_token
  end
end
