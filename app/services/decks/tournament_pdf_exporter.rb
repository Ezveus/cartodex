require "prawn"
require "prawn/table"

class Decks::TournamentPdfExporter < ApplicationService
  class OverflowError < StandardError; end

  BASE_FONT = 11
  ROW_FONT = 10
  SECTION_SPACING = 12
  MIN_ROW_PADDING = 2
  MAX_ROW_PADDING = 6

  def initialize(deck, profile)
    @deck = deck
    @profile = profile
  end

  def call
    # Tables span the full page width, stacked vertically. If the content
    # doesn't fit on one page, shrink the row padding and retry.
    padding = MAX_ROW_PADDING
    pdf = build_pdf(padding)

    while pdf.page_count > 1 && padding > MIN_ROW_PADDING
      padding -= 1
      pdf = build_pdf(padding)
    end

    raise OverflowError, "Decklist did not fit on a single page" if pdf.page_count > 1

    pdf.render
  end

  private

  def build_pdf(row_padding)
    @row_padding = row_padding
    pdf = Prawn::Document.new(page_size: "A4", margin: 30)

    render_profile(pdf)
    pdf.move_down 14
    render_pokemon_section(pdf)
    pdf.move_down SECTION_SPACING
    render_trainer_section(pdf)
    pdf.move_down SECTION_SPACING
    render_energy_section(pdf)

    pdf
  end

  def render_profile(pdf)
    data = [ [
      "Player", @profile.player_name,
      "ID", @profile.player_id,
      "DOB", @profile.date_of_birth.iso8601,
      "Division", @profile.division.to_s.capitalize
    ] ]
    pdf.table(data, cell_style: { borders: [], padding: [ 1, 6, 1, 0 ], size: BASE_FONT }) do
      columns([ 0, 2, 4, 6 ]).font_style = :bold
    end
  end

  def render_pokemon_section(pdf)
    rows = pokemon_rows
    section(pdf, "Pokémon", rows.sum { |r| r[:quantity] })
    return if rows.empty?

    data = [ [ "#", "Name", "Set", "No.", "Reg." ] ]
    rows.each do |r|
      data << [ r[:quantity].to_s, r[:name], r[:set_name], r[:set_number], r[:regulation_mark] || "" ]
    end
    render_section_table(pdf, data, column_widths: { 0 => 40, 3 => 60, 4 => 60 })
  end

  def render_trainer_section(pdf)
    rows = trainer_rows
    section(pdf, "Trainer", rows.sum { |r| r[:quantity] })
    return if rows.empty?

    data = [ [ "#", "Name" ] ]
    rows.each { |r| data << [ r[:quantity].to_s, r[:name] ] }
    render_section_table(pdf, data, column_widths: { 0 => 40 })
  end

  def render_energy_section(pdf)
    rows = energy_rows
    section(pdf, "Energy", rows.sum { |r| r[:quantity] })
    return if rows.empty?

    data = [ [ "#", "Name", "Type" ] ]
    rows.each { |r| data << [ r[:quantity].to_s, r[:name], r[:kind] ] }
    render_section_table(pdf, data, column_widths: { 0 => 40, 2 => 80 })
  end

  def render_section_table(pdf, data, column_widths: {})
    pdf.table(data, header: true, width: pdf.bounds.width, cell_style: { size: ROW_FONT, padding: @row_padding }) do
      row(0).font_style = :bold
      row(0).background_color = "DDDDDD"
      columns(0).align = :right
      column_widths.each { |col, width| columns(col).width = width }
    end
  end

  def section(pdf, label, total)
    pdf.text "#{label} — #{total}", size: BASE_FONT + 1, style: :bold
    pdf.move_down 2
  end

  # Pokémon: group by (name, set_name, set_number). A specific printing is a
  # distinct entry — Budew PRE 4 and Budew ASC 16 are not merged.
  def pokemon_rows
    @pokemon_rows ||= begin
      grouped = deck_cards_by_type("Pokémon").group_by do |dc|
        [ dc.card.name, dc.card.set_name, dc.card.set_number ]
      end

      grouped.map do |(name, set_name, set_number), dcs|
        {
          name: name,
          set_name: set_name,
          set_number: set_number,
          regulation_mark: dcs.first.card.regulation_mark,
          quantity: dcs.sum(&:quantity)
        }
      end.sort_by { |r| [ r[:name], r[:set_name], r[:set_number] ] }
    end
  end

  # Trainer: group by name only. Boss's Orders ASC 183 and Boss's Orders MEG 114
  # are merged into a single row.
  def trainer_rows
    @trainer_rows ||= begin
      grouped = deck_cards_by_type("Trainer").group_by { |dc| dc.card.name }
      grouped.map { |name, dcs| { name: name, quantity: dcs.sum(&:quantity) } }
            .sort_by { |r| r[:name] }
    end
  end

  # Energy: group by name. Distinguish Basic vs Special via the card subtype.
  def energy_rows
    @energy_rows ||= begin
      grouped = deck_cards_by_type("Energy").group_by { |dc| dc.card.name }
      grouped.map do |name, dcs|
        basic = dcs.first.card.subtype == "Basic Energy"
        { name: name, kind: basic ? "Basic" : "Special", quantity: dcs.sum(&:quantity) }
      end.sort_by { |r| [ r[:kind], r[:name] ] }
    end
  end

  def deck_cards_by_type(type)
    @deck.deck_cards.select { |dc| dc.card.card_type == type }
  end
end
