class ApplicationService
  def self.call(...)
    new(...).call
  end

  private

  # Runs the block so that concurrent writers are serialized on SQLite via
  # BEGIN IMMEDIATE (the write lock is taken before any read inside the block,
  # so read-then-write allocation decisions can't race). That is what a plain
  # top-level transaction already does: the SQLite3 adapter begins every one of
  # them in `immediate` mode. Asking for it through `isolation:` instead raises
  # TransactionIsolationError — that option means an ANSI isolation level, of
  # which SQLite offers only `read_uncommitted`, and `immediate` is a
  # transaction *mode*, not a level.
  #
  # When already inside a transaction (e.g. transactional test fixtures, or a
  # caller's transaction), a nested `requires_new` opens a savepoint — correct
  # single-threaded behavior, just without the extra write-lock serialization,
  # which the enclosing BEGIN IMMEDIATE has taken anyway.
  def serialized_transaction(&block)
    if ActiveRecord::Base.connection.transaction_open?
      ActiveRecord::Base.transaction(requires_new: true, &block)
    else
      ActiveRecord::Base.transaction(&block)
    end
  end
end
