# A bulk card add is relative — it adds copies rather than setting them — so the one question
# asked of it afterwards is "what did it actually do to each printing", which neither the label
# nor the collection's current quantity can answer once a second run has happened. The receipt is
# that answer, written once at the end of the run: one object per resolved printing, carrying the
# printing, the copies added and the before/after it moved through.
#
# JSON rather than a join table, for the reason created_standing_ids gives: it is read whole by a
# human — the admin imports table discloses it inline — and never joined, aggregated or indexed.
# `default: []` and NOT NULL together are what let every reader index into the array without first
# asking whether it is nil, including on the rows every other kind of import writes, which simply
# never fill it.
class AddReceiptToImports < ActiveRecord::Migration[8.1]
  def change
    change_table :imports do |t|
      t.json :receipt, null: false, default: []
    end
  end
end
