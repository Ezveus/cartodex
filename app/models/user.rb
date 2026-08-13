class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :collections, dependent: :destroy
  has_many :cards, through: :collections
  has_many :decks, dependent: :destroy
  has_many :imports, dependent: :destroy
  has_many :tournament_profiles, dependent: :destroy
  has_many :tournaments, dependent: :destroy

  # Lifetime options offered when generating a token. nil means "never expires",
  # stored as a NULL api_token_expires_at. This Hash is the single definition of
  # both the allowed keys and the default, so the model and the form can never
  # disagree about what "default" means.
  TOKEN_LIFETIMES = { "30d" => 30.days, "90d" => 90.days, "1y" => 1.year, "never" => nil }.freeze
  DEFAULT_LIFETIME_KEY = "90d"

  # How coarsely api_token_last_used_at is recorded. The MCP auth path runs on
  # every tool call, and SQLite serialises writes, so the stamp is throttled to
  # one write per user per interval. "Last used" can therefore lag reality by up
  # to this much, which is expected — the UI must not imply finer precision.
  USAGE_TOUCH_INTERVAL = 1.hour

  # How long the usage stamp may wait for SQLite's write lock. See
  # #touch_api_token_usage for why it is this short.
  USAGE_TOUCH_WRITE_WAIT_MS = 50

  # Resolves an untrusted lifetime key to a duration, in the one place both the
  # settings form and lib/tasks/mcp.rake go through, so they cannot drift apart
  # on what the options are. An unknown key yields the default: the form posts
  # whatever the browser sends it, and a bad value there must not raise. Callers
  # able to report the mistake to a human check #lifetime_key? first instead of
  # coercing silently — that difference is deliberate, not an inconsistency.
  def self.lifetime_for(key)
    TOKEN_LIFETIMES.fetch(key) { TOKEN_LIFETIMES.fetch(DEFAULT_LIFETIME_KEY) }
  end

  def self.lifetime_key?(key)
    TOKEN_LIFETIMES.key?(key)
  end

  def self.generate_api_token
    SecureRandom.base58(24)
  end

  def self.digest_api_token(raw)
    Digest::SHA256.hexdigest(raw)
  end

  # Returns the user matching a presented raw token, or nil. Lookup is by
  # digest of the presented value, so the stored secret is never compared
  # in plaintext and the query does not leak timing about the real token.
  # An expired token is rejected before its usage is recorded: expiry must
  # leave no trace of use.
  def self.authenticate_api_token(raw)
    return if raw.blank?

    user = find_by(api_token_digest: digest_api_token(raw))
    return if user.nil? || user.api_token_expired?

    user.touch_api_token_usage
    user
  end

  # Generates a new token, stores only its digest, and returns the raw token.
  # The raw value is shown only here (never persisted), so it cannot be
  # retrieved later — only rotated. `expires_in` of nil means never expires.
  def regenerate_api_token(expires_in: TOKEN_LIFETIMES.fetch(DEFAULT_LIFETIME_KEY))
    raw = self.class.generate_api_token
    now = Time.current
    update!(
      api_token_digest: self.class.digest_api_token(raw),
      api_token_created_at: now,
      api_token_expires_at: expires_in && now + expires_in,
      api_token_last_used_at: nil
    )
    raw
  end

  # Leaves the user with no token at all, rather than an unusable one.
  def revoke_api_token!
    update!(
      api_token_digest: nil,
      api_token_created_at: nil,
      api_token_expires_at: nil,
      api_token_last_used_at: nil
    )
  end

  def api_token?
    api_token_digest.present?
  end

  def api_token_expired?
    api_token_expires_at.present? && api_token_expires_at.past?
  end

  def api_token_used_recently?
    api_token_last_used_at.present? && api_token_last_used_at > USAGE_TOUCH_INTERVAL.ago
  end

  # Which TOKEN_LIFETIMES key the current token was issued with, so the form can
  # show it back instead of resetting to the default and contradicting the expiry
  # it displays right above. Derived rather than stored: created_at and
  # expires_at are stamped from the same Time.current, so their difference is
  # exactly the duration that was picked. Falls back to the default when there is
  # no token, and when the span matches no current option — a token issued under
  # an option that has since been removed still has to render something.
  def api_token_lifetime_key
    return DEFAULT_LIFETIME_KEY unless api_token?
    return "never" if api_token_expires_at.nil?
    return DEFAULT_LIFETIME_KEY if api_token_created_at.nil?

    # Replays the addition regenerate_api_token made rather than comparing the
    # span to duration.to_i: 1.year advances the calendar by a year (365 days
    # here), while its to_i is the average Gregorian year of 365.2425 days, so a
    # numeric comparison never matches the option the user actually picked.
    TOKEN_LIFETIMES.find { |_key, duration|
      duration && (api_token_created_at + duration).to_i == api_token_expires_at.to_i
    }&.first || DEFAULT_LIFETIME_KEY
  end

  # This runs in a before_action, ahead of any service opening a
  # BEGIN IMMEDIATE transaction — it is that ordering, not the absence of
  # validations or callbacks, that keeps a single-column update_column clear
  # of ApplicationService#serialized_transaction.
  #
  # Best-effort: this is a telemetry write, not part of the request's
  # business outcome. Nothing it can hit — a busy write lock, a full disk, a
  # read-only mount — may fail an otherwise-valid MCP call just to record when
  # it happened, so the rescue is the whole StatementInvalid family. Only the
  # busy case arrives as its StatementTimeout subclass; SQLITE_FULL and
  # SQLITE_READONLY surface as bare StatementInvalid, and catching just the
  # subclass turned a read-only tool call into a 500.
  def touch_api_token_usage
    return if api_token_used_recently?

    with_brief_write_wait do
      update_column(:api_token_last_used_at, Time.current)
    end
  rescue ActiveRecord::StatementInvalid
    nil
  end

  private

  # Caps how long the usage stamp waits for SQLite's write lock. Everything else
  # on the MCP auth path is a read, so without this cap a tool call could sit for
  # the connection's full busy_timeout (5 s, config/database.yml) behind an
  # unrelated writer — once per user per USAGE_TOUCH_INTERVAL, and again on every
  # call until the contention clears, because a stamp that failed leaves the next
  # call due for the same wait. 50 ms wins an uncontended lock and is invisible
  # next to a tool call; losing it costs an hour of stamp precision, which the UI
  # already rounds away.
  def with_brief_write_wait
    connection = self.class.connection
    return yield unless connection.adapter_name == "SQLite"

    previous = connection.query_value("PRAGMA busy_timeout")
    connection.execute("PRAGMA busy_timeout = #{USAGE_TOUCH_WRITE_WAIT_MS}")
    begin
      yield
    ensure
      connection.execute("PRAGMA busy_timeout = #{previous.to_i}")
    end
  end
end
