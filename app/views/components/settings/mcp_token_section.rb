module Settings
  # The MCP token panel. Rendered on page load with raw_token nil, and
  # re-rendered by McpTokensController#create with the freshly generated token
  # so it can be shown exactly once. The root id is the Turbo Stream target.
  class McpTokenSection < ApplicationComponent
    def initialize(user:, raw_token: nil)
      @user = user
      @raw_token = raw_token
    end

    def view_template
      section(id: "mcp-token", class: "settings-section") do
        h2 { "MCP token" }
        p(class: "settings-section-lead") do
          plain "A bearer token lets an MCP client manage your collection and decks on your behalf."
        end
        reveal if @raw_token
        metadata
        generate_form
        revoke_button if @user.api_token?
      end
    end

    private

    # Shown exactly once, right after generation: the value is not recoverable
    # from the digest, so this is the user's only chance to copy it.
    def reveal
      # turbo_temporary: Turbo Drive caches this element in the page snapshot
      # it takes before navigating away. Without this, pressing Back restores
      # the snapshot with the raw token still visible — in-memory only, not a
      # persistence leak, but it breaks the "shown once" guarantee on Back/
      # Forward. Turbo removes temporary elements from the snapshot before
      # caching it.
      div(class: "settings-reveal", data: { turbo_temporary: true }) do
        p(class: "settings-reveal-warning") do
          strong { "Copy this now." }
          plain " It will not be shown again — only rotated."
        end
        code(id: "mcp-token-value", class: "settings-reveal-value") { @raw_token }
        button(
          type: "button",
          class: "btn btn-secondary btn-sm",
          data: {
            controller: "clipboard",
            clipboard_text_value: @raw_token,
            action: "clipboard#copy"
          }
        ) { "Copy" }
        h3 { "Client configuration" }
        pre(class: "settings-reveal-snippet") { client_config_snippet }
      end
    end

    def client_config_snippet
      <<~SNIPPET
        Endpoint:      #{mcp_url}
        Authorization: Bearer #{@raw_token}
      SNIPPET
    end

    def metadata
      if @user.api_token?
        dl(class: "settings-meta") do
          meta_row("Created") { plain format_time(@user.api_token_created_at) }
          meta_row("Expires") { expiry_value }
          meta_row("Last used") { plain last_used_text }
        end
      else
        p(class: "settings-empty") { "No token. Generate one to connect an MCP client." }
      end
    end

    # Takes a block rather than a value: the expiry cell emits an element (the
    # Expired badge), and a method that emits writes to the buffer where it is
    # *called*, not where its return value lands — so passing a value would
    # render the badge outside the <dd>.
    def meta_row(label_text, &block)
      div(class: "settings-meta-row") do
        dt { label_text }
        dd(&block)
      end
    end

    def expiry_value
      if @user.api_token_expires_at.nil?
        plain "Never"
      elsif @user.api_token_expired?
        span(class: "badge badge-danger") { "Expired" }
        plain " #{format_time(@user.api_token_expires_at)}"
      else
        plain "#{format_time(@user.api_token_expires_at)} (in #{distance_of_time_in_words_to_now(@user.api_token_expires_at)})"
      end
    end

    # The stamp is throttled to one write per hour, so the copy must never claim
    # finer precision than that. distance_of_time_in_words_to_now returns
    # minute-granular strings under 45 minutes ("12 minutes"), which would read
    # as fresher than the data can possibly be — a value stamped 12 minutes ago
    # may describe a request from an hour and 12 minutes ago. Anything inside the
    # throttle window therefore collapses to one bucket; above it, the helper is
    # already hour-granular and can be used as-is.
    def last_used_text
      return "Never used" if @user.api_token_last_used_at.nil?
      return "Used within the last hour" if @user.api_token_used_recently?

      "#{distance_of_time_in_words_to_now(@user.api_token_last_used_at).capitalize} ago"
    end

    def format_time(time)
      time.nil? ? "—" : time.to_date.to_s
    end

    def generate_form
      form_with url: mcp_token_path, method: :post, class: "settings-form" do |f|
        render Ui::FormGroup.new(label: "Expires in", field_name: "lifetime") do
          f.select :lifetime,
            [ [ "30 days", "30d" ], [ "90 days", "90d" ], [ "1 year", "1y" ], [ "Never", "never" ] ],
            { selected: User::DEFAULT_LIFETIME_KEY },
            class: "form-input", name: "lifetime"
        end
        render Ui::Button.new(label: @user.api_token? ? "Rotate token" : "Generate token")
        if @user.api_token?
          em(class: "form-hint") { "Rotating makes the current token stop working immediately." }
        end
      end
    end

    def revoke_button
      form_with url: mcp_token_path, method: :delete, id: "mcp-token-revoke", class: "settings-form" do
        render Ui::Button.new(
          label: "Revoke token",
          variant: :danger,
          data: { turbo_confirm: "Revoke the token? Any MCP client using it stops working." }
        )
      end
    end
  end
end
