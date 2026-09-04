# Case-insensitive, Unicode-safe substring matching on a model's `name`.
#
# Matching runs against `name_normalized` (a mirror of `name`, Unicode-downcased by the callback
# below) rather than against `name`, because SQLite's LIKE only folds ASCII A–Z:
# `name LIKE '%POKÉMON%'` never matches "Pokémon", so an accented query in the wrong case
# silently returned nothing. Normalising both sides in Ruby makes the fold Unicode-aware and
# keeps the comparison a plain LIKE the database can run.
#
# Including models need `name` and `name_normalized` string columns. Fixtures are inserted
# without callbacks, so their YAML must spell `name_normalized` out by hand — each including
# model has a test asserting the two stay in step.
module NameNormalizable
  extend ActiveSupport::Concern

  # LIKE '%…%' can't use an index, so every match is a scan whose cost is O(rows × pattern) —
  # and the spotlight fires one per keystroke on the whole card catalog, unthrottled. Nothing
  # the app stores in a `name` comes close to this, so capping the pattern here costs no real
  # query its matches while putting a ceiling on what a single request can make the database do.
  MAX_QUERY_LENGTH = 100

  included do
    before_save :normalize_name

    scope :name_matching, ->(query) {
      where("#{table_name}.name_normalized LIKE ? ESCAPE '\\'", "%#{normalize_for_match(query)}%")
    }
  end

  class_methods do
    # Downcased and LIKE-escaped, ready to be wrapped in `%…%`.
    #
    # The query's LIKE metacharacters are escaped so a `%` or `_` typed by a user matches
    # literally instead of acting as a wildcard. ESCAPE is required, not decorative:
    # sanitize_sql_like escapes with a backslash, but SQLite's LIKE has no default escape
    # character, so without the clause the backslash itself would be matched. ESCAPE is standard
    # SQL, so this survives the move to PostgreSQL contemplated in #62.
    #
    # The cap is applied before the escaping, not after: sanitize_sql_like doubles backslashes, so
    # truncating its output could cut a `\\` in half and leave a dangling escape that changes what
    # the pattern means.
    def normalize_for_match(query)
      sanitize_sql_like(query.to_s.squish.downcase.first(MAX_QUERY_LENGTH))
    end
  end

  # Mirror of `name`, squished and Unicode-downcased, so name_matching can search with a plain
  # LIKE instead of depending on the database's own case folding.
  #
  # squish, not merely downcase: on Tournament this value is half of a UNIQUE key, and a name
  # arrives copy-pasted — with a trailing space, or a double space where a line wrapped — far
  # more often than it arrives typed, so without it one real event gets two catalog rows that
  # render identically. `name` itself keeps whatever the user typed; only the key is folded.
  #
  # The query side (normalize_for_match) squishes too, and must: fold only what is stored and a
  # name typed with a double space becomes unfindable.
  def normalize_name
    self.name_normalized = name&.squish&.downcase
  end
end
