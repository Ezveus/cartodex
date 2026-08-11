namespace :mcp do
  desc "Rotate a user's MCP API token and print the new raw value (shown once, not retrievable later). Lifetime is one of 30d/90d/1y/never, defaulting to 90d. Usage: bin/rails 'mcp:token[email@example.com,30d]'"
  task :token, [ :email, :lifetime ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    key = args[:lifetime].presence || User::DEFAULT_LIFETIME_KEY

    unless User::TOKEN_LIFETIMES.key?(key)
      abort "Unknown lifetime #{key.inspect}. Valid values: #{User::TOKEN_LIFETIMES.keys.join(', ')}."
    end

    raw = user.regenerate_api_token(expires_in: User::TOKEN_LIFETIMES.fetch(key))
    puts raw
  end
end
