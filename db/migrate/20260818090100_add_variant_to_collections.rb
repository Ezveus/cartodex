class AddVariantToCollections < ActiveRecord::Migration[8.1]
  # A collections row stops being "this user owns this printing" and becomes
  # "this user owns this printing in this variant". The "unknown" sentinel keeps
  # the old shape available: a user who does not care about language or finish
  # still has exactly one row per printing.
  #
  # null: false is not cosmetic. SQLite treats two NULLs as distinct in a unique
  # index, so with nullable columns (user, card, NULL, NULL) would insert twice
  # and the widened uniqueness would protect nothing. CollectionTest pins that
  # with its own test — the uniqueness test next to it cannot, since it inserts
  # rows taking the column default and so stays green either way.
  #
  # Order is load-bearing: the columns arrive before the index, and because
  # existing rows are already unique on (user_id, card_id), adding two constant
  # columns leaves them unique — this migration cannot fail going forward.
  #
  # It can fail going *back*, and only once the feature has been used: the
  # inverse of `change` re-creates the narrow unique index before dropping the
  # columns that made the rows distinct, so a database holding a printing split
  # across two variants cannot roll this back without first deciding how to merge
  # them. SQLite runs DDL in a transaction, so the failed rollback leaves the
  # schema untouched rather than half-migrated.
  #
  # `foil` is dropped rather than migrated: nothing has ever read or written it
  # (it is absent from the API's permit list, every service, every view and every
  # MCP tool), and `finish` supersedes it. Issue #89 required that dead column to
  # be given a meaning or removed.
  def change
    add_column :collections, :language, :string, null: false, default: "unknown"
    add_column :collections, :finish, :string, null: false, default: "unknown"
    remove_column :collections, :foil, :boolean

    remove_index :collections, [ :user_id, :card_id ], unique: true
    add_index :collections, [ :user_id, :card_id, :language, :finish ],
      unique: true, name: "index_collections_on_user_card_and_variant"
  end
end
