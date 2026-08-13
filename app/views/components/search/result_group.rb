module Search
  # One group of spotlight results: its header, its rows (rendered by the caller's block, since
  # each type has its own path and metadata) and the link to that type's index, pre-filtered.
  class ResultGroup < ApplicationComponent
    def initialize(key:, label:, records:, total:, index_path:, see_all_label:)
      @key = key
      @label = label
      @records = records
      @total = total
      @index_path = index_path
      @see_all_label = see_all_label
    end

    def view_template(&row)
      return if @records.empty?

      div(role: "group", aria_labelledby: header_id, class: "spotlight-group") do
        div(class: "spotlight-group-header", id: header_id) { header_text }
        @records.each { |record| row.call(record) }
        link_to @see_all_label, @index_path, class: "spotlight-see-all", data: { turbo_frame: "_top" }
      end
    end

    private

    def header_id
      "spotlight-group-#{@key}"
    end

    # "DECKS · 3" when everything fits, "DECKS · 5 of 12" when the cap truncated it.
    def header_text
      count = @records.size < @total ? "#{@records.size} of #{@total}" : @total.to_s
      "#{@label} · #{count}"
    end
  end
end
