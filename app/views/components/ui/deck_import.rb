# frozen_string_literal: true

module Ui
  class DeckImport < ApplicationComponent
    def initialize(pending_imports: [])
      @pending_imports = pending_imports
    end

    def view_template
      render Ui::ImportingList.new(
        pending_imports: @pending_imports,
        item_id_prefix: "importing",
        extra_data: { decks_target: "importingList" }
      )
      render Ui::DeckImportModal.new
    end
  end
end
