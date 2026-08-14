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
        see_all_option
      end
    end

    private

    # role="option", like the rows above it: a listbox may only contain options and groups, so a
    # plain link here made the whole panel invalid ARIA. Being an option also puts it in the
    # keyboard walk, one step past the last row of its group — which is where a user who read the
    # five results and wants the rest would look for it.
    def see_all_option
      a(
        id: "#{header_id}-see-all",
        href: @index_path,
        role: "option",
        aria_selected: "false",
        class: "spotlight-see-all",
        data: { turbo_frame: "_top" }
      ) { @see_all_label }
    end

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
