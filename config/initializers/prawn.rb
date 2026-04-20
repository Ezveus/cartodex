require "prawn"

# Silence Prawn's warning about limited UTF-8 support in the built-in fonts.
# Card names stay within Latin-1 (e.g. "Pokémon"), which Helvetica handles.
Prawn::Fonts::AFM.hide_m17n_warning = true
