namespace :mcp do
  desc "Rotate a user's MCP API token and print the new raw value (shown once, not retrievable later). Lifetime is one of 30d/90d/1y/never, defaulting to 90d. Usage: bin/rails 'mcp:token[email@example.com,30d]'"
  task :token, [ :email, :lifetime ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    key = args[:lifetime].presence || User::DEFAULT_LIFETIME_KEY

    # A typo on the command line is worth reporting, unlike an unexpected value
    # posted by a browser — hence the check the form does not do.
    unless User.lifetime_key?(key)
      abort "Unknown lifetime #{key.inspect}. Valid values: #{User::TOKEN_LIFETIMES.keys.join(', ')}."
    end

    raw = user.regenerate_api_token(expires_in: User.lifetime_for(key))
    puts raw

    # On stderr, so `bin/rails 'mcp:token[…]' > token.txt` still captures the
    # token alone. Said out loud because the single-argument form used to mint a
    # token that never expired: nothing in the app announces an expiry, and an
    # MCP client whose token lapses just starts failing every call with a 401
    # that deliberately looks the same as an invalid one.
    expiry = user.api_token_expires_at
    warn "Lifetime #{key}: #{expiry ? "expires #{expiry.to_date}" : 'never expires'}."
  end
end
