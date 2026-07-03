class ApplicationService
  def self.call(...)
    new(...).call
  end

  private

  # Runs the block so that concurrent writers are serialized on SQLite via
  # BEGIN IMMEDIATE (the write lock is taken before any read inside the block,
  # so read-then-write allocation decisions can't race). When already inside a
  # transaction (e.g. transactional test fixtures, or a caller's transaction),
  # isolation can't be set, so it degrades to a nested savepoint — correct
  # single-threaded behavior, just without the extra write-lock serialization.
  def serialized_transaction(&block)
    if ActiveRecord::Base.connection.transaction_open?
      ActiveRecord::Base.transaction(requires_new: true, &block)
    else
      ActiveRecord::Base.transaction(isolation: :immediate, &block)
    end
  end
end
