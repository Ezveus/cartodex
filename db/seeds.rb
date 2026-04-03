# Pokémon Subtypes reference data
[
  { name: "Pokémon ex", rule_box: true, prize_cards_on_ko: 2,
    rule_text: "When your Pokémon ex is Knocked Out, your opponent takes 2 Prize cards." },
  { name: "Mega Evolution ex", rule_box: true, prize_cards_on_ko: 3,
    rule_text: "When your Mega Evolution ex is Knocked Out, your opponent takes 3 Prize cards." },
  { name: "Tera Pokémon ex", rule_box: true, prize_cards_on_ko: 2,
    rule_text: "As long as this Pokémon is on your Bench, prevent all damage done to this Pokémon by attacks. When your Tera Pokémon ex is Knocked Out, your opponent takes 2 Prize cards." },
  { name: "Pokémon V", rule_box: true, prize_cards_on_ko: 2,
    rule_text: "When your Pokémon V is Knocked Out, your opponent takes 2 Prize cards." },
  { name: "Pokémon VMAX", rule_box: true, prize_cards_on_ko: 3,
    rule_text: "When your Pokémon VMAX is Knocked Out, your opponent takes 3 Prize cards." },
  { name: "Pokémon VSTAR", rule_box: true, prize_cards_on_ko: 2,
    rule_text: "When your Pokémon VSTAR is Knocked Out, your opponent takes 2 Prize cards." },
  { name: "Pokémon V-UNION", rule_box: true, prize_cards_on_ko: 3,
    rule_text: "When your Pokémon V-UNION is Knocked Out, your opponent takes 3 Prize cards." },
  { name: "Pokémon EX", rule_box: true, prize_cards_on_ko: 2,
    rule_text: "When your Pokémon-EX is Knocked Out, your opponent takes 2 Prize cards." }
].each do |attrs|
  PokemonSubtype.find_or_create_by!(name: attrs[:name]) do |st|
    st.rule_box = attrs[:rule_box]
    st.prize_cards_on_ko = attrs[:prize_cards_on_ko]
    st.rule_text = attrs[:rule_text]
  end
end
