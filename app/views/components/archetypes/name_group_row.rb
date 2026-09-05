module Archetypes
  # One card name, and — when the name is played as more than one card — the printings underneath
  # it.
  #
  # The sub-rows are deliberately **not** presented as a breakdown of the row above them. A list
  # may hold two printings of one name, so the per-printing shares can total more than the
  # name-level one: measured on the production data, Hoothoot sits at 73.1% of lists while its
  # three printings read 69.9, 39.8 and 2.2. A reader who takes those as parts of a whole
  # concludes the wrong thing about every one of them, so the group says so in words rather than
  # trusting the indentation to imply it.
  #
  # Copies live on the printing, never on the name, for the same reason: two versions of one name
  # in one list are two rows of copies, and a "1-4" spanning them would describe no list.
  class NameGroupRow < ApplicationComponent
    def initialize(group:, single_list: false)
      @group = group
      @single_list = single_list
    end

    def view_template
      li(class: "archetype-card-row") do
        main_line
        printings if @group.split?
      end
    end

    private

    def main_line
      div(class: "archetype-card-main") do
        div(class: "archetype-card-name") do
          span(class: "archetype-card-name-text") { @group.name }
          fixed_flag if fixed_group?
          label_flags(type_labels)
        end
        share(@group.inclusion_pct, @group.inclusion_count)
        div(class: "archetype-card-copies") { name_copies_text }
      end
    end

    # A name is only "fixed" when it is one card. A name split across printings can be in every
    # list at a settled count and still be a choice — which printing — so the flag would claim
    # something the data does not say.
    def fixed_group?
      !@group.split? && fixed?(@group.entries.first)
    end

    # `Entry#fixed?` is `core && single_quantity?`, and `core` is `inclusion_count == lists_count`
    # — so at one list every entry is fixed by construction and the flag reports the sample size
    # rather than the archetype. Archetypes::CardReport says that once, in words, and the rows say
    # nothing.
    def fixed?(entry)
      !@single_list && entry.fixed?
    end

    def fixed_flag
      span(class: "badge badge-format archetype-fixed-flag",
           title: "Played by every list in this sample, always in the same number") { "fixed" }
    end

    # A type label annotates the card and never opens a section: an ACE SPEC is still an Item,
    # and moving it out would stop the category counts being a partition of the list.
    #
    # Withheld on a split group for the same reason `fixed_group?` withholds its flag there: a
    # name-level badge asserts a property of every printing under it, and a split name's printings
    # are genuinely different cards that may not agree on their labels — the name line would then
    # claim the union as if it were settled, with no way for the reader to see which printing
    # actually carries which label. So the name line says nothing, and each printing's own row
    # (see `printings` below) carries its own labels instead — no information is lost, only moved
    # to where it is true.
    def type_labels
      return [] if @group.split?

      labels_for(@group.entries)
    end

    # Filtered to `type?` here rather than in the service: `CardStats` loads both families in one
    # query so stage 2's role mode can reuse the same load, and only this render layer knows
    # stage 1 badges type labels alone. Reads every entry passed in, not just one printing's, then
    # re-sorts by [position, slug] once several entries' labels are concatenated, restoring the
    # ordering `CardStats` already guarantees within one entry but not across several.
    def labels_for(entries)
      entries.flat_map(&:labels).select(&:type?).uniq.sort_by { |label| [ label.position, label.slug ] }
    end

    # Each label gets its own full-width wrapper: see the CSS comment on .archetype-card-label-line
    # for why the wrap-forcing element and the visible pill cannot be the same element.
    def label_flags(labels)
      labels.each do |label|
        span(class: "archetype-card-label-line") do
          span(class: "badge archetype-card-label", title: label.description) { label.name }
        end
      end
    end

    def name_copies_text
      return "#{@group.entries.size} printings" if @group.split?

      copies_text(@group.entries.first)
    end

    def printings
      ul(class: "archetype-printing-list") do
        @group.entries.each do |entry|
          li(class: "archetype-printing-row") do
            div(class: "archetype-card-name") do
              plain entry.card.printing_label
              fixed_flag if fixed?(entry)
              label_flags(labels_for([ entry ]))
            end
            share(entry.inclusion_pct, entry.inclusion_count)
            div(class: "archetype-card-copies") { copies_text(entry) }
          end
        end
      end

      p(class: "archetype-printing-note") do
        "A list may play more than one of these printings, so their shares are not parts of the " \
          "#{format_pct(@group.inclusion_pct)}% above and can add up past it."
      end
    end

    def share(pct, count)
      div(class: "archetype-card-share") do
        # Presentational: the number is right beside it in text, so a screen reader that read the
        # bar too would say everything twice.
        div(class: "archetype-bar", aria_hidden: "true") do
          div(class: "archetype-bar-fill", style: "width: #{format_pct([ pct, 100 ].min)}%")
        end
        span(class: "archetype-card-pct") do
          "#{format_pct(pct)}% of lists (#{count})"
        end
      end
    end

    def copies_text(entry)
      parts = [ "#{copies_range(entry)} #{copies_noun(entry)}" ]
      parts << mode_text(entry) unless entry.single_quantity?
      parts.join(" · ")
    end

    def copies_range(entry)
      return entry.min_copies.to_s if entry.single_quantity?

      "#{entry.min_copies}-#{entry.max_copies}"
    end

    def copies_noun(entry)
      entry.single_quantity? && entry.min_copies == 1 ? "copy" : "copies"
    end

    # A tie is a real answer and is said to be one. Printing "3 / 4" alone reads as a range or a
    # typo; silently picking 3 would state a consensus this sample does not hold.
    def mode_text(entry)
      return "most often #{entry.modes.join(' / ')} — tied" if entry.tied_mode?

      "most often #{entry.modes.first}"
    end

    # 100.0 and 73.1 both arrive as Floats rounded to one decimal. A trailing ".0" on a whole
    # percentage is noise on a page that prints dozens of them.
    #
    # Kernel.format explicitly: phlex-rails defines its own zero-argument `format` on the
    # component, so the bare call raises ArgumentError rather than formatting anything.
    def format_pct(pct)
      pct == pct.round ? pct.round.to_s : Kernel.format("%.1f", pct)
    end
  end
end
