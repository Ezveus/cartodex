module Styleguide
  # Living reference for the Cartodex design system. Renders real UI
  # components and the actual CSS tokens (via var(--token)) so the page can
  # never drift from the code it documents.
  class PageView < ApplicationComponent
    NEUTRALS = [
      [ "Ink 900", "--ink-900" ], [ "Ink 700", "--ink-700" ], [ "Ink 500", "--ink-500" ],
      [ "Ink 300", "--ink-300" ], [ "Line", "--line" ], [ "Paper", "--paper" ], [ "Surface", "--surface" ]
    ].freeze

    BRAND = [
      [ "Flare — action", "--flare" ], [ "Flare ink — hover", "--flare-ink" ], [ "Water strong", "--water-strong" ]
    ].freeze

    # [French label, energy type] — slug is the downcased type, colour token
    # comes from Card::TYPE_TOKENS (the single source of truth).
    ENERGIES = [
      [ "Plante", "Grass" ], [ "Feu", "Fire" ], [ "Eau", "Water" ], [ "Foudre", "Lightning" ],
      [ "Combat", "Fighting" ], [ "Psy", "Psychic" ], [ "Obscurité", "Darkness" ], [ "Métal", "Metal" ],
      [ "Fée", "Fairy" ], [ "Dragon", "Dragon" ], [ "Incolore", "Colorless" ]
    ].freeze

    RESULTS = [
      [ "win", "Victoire" ], [ "loss", "Défaite" ], [ "draw", "Nul" ], [ "timeout", "Temps écoulé" ]
    ].freeze

    TYPE_SCALE = [
      [ "Display / 3xl · 800", "sg-ts-3xl", "Charizard ex — Pidgeot" ],
      [ "Display / 2xl · 700", "sg-ts-2xl", "Mes decks compétitifs" ],
      [ "Display / xl · 700", "sg-ts-xl", "Détail de l'archétype" ],
      [ "Body / base · 400", "sg-ts-base", "Suis tes matchups et exporte vers le format tournoi." ],
      [ "Body / sm · 400", "sg-ts-sm", "Dernière mise à jour il y a 2 heures · BO3" ],
      [ "Mono / sm", "sg-ts-mono", "PAF 054/091 · 67.5% WR" ]
    ].freeze

    def view_template
      content_for(:title) { "Styleguide — Cartodex" }

      div(class: "sg") do
        hero
        colors_section
        energy_section
        results_section
        typography_section
        buttons_section
        badges_section
        stats_section
        form_section
        deck_card_section
        tokens_section
      end
    end

    private

    def hero
      header(class: "sg-hero", style: "margin-bottom: 2rem") do
        span(class: "sg-tag") { "Design system · référence vivante" }
        h1 { "Cartodex" }
        p(class: "sg-lead") do
          plain "Le langage visuel de l'app : chrome ardoise, palette par type d'énergie, "
          plain "vernis holo. Cette page rend les composants et tokens réels — elle ne ment jamais."
        end
      end
    end

    def sg_section(eyebrow, title, lead = nil)
      div(class: "sg-section") do
        p(class: "sg-eyebrow") { eyebrow }
        h2 { title }
        p { lead } if lead
        yield
      end
    end

    def swatch(name, var)
      div(class: "sg-swatch") do
        div(class: "chip", style: "background: var(#{var})")
        div(class: "meta") do
          div(class: "name") { name }
          div(class: "val") { var }
        end
      end
    end

    def colors_section
      sg_section("Fondations", "Couleur") do
        p(class: "sg-eyebrow", style: "margin-top: 1rem") { "Neutres & chrome" }
        div(class: "sg-grid") { NEUTRALS.each { |name, var| swatch(name, var) } }
        p(class: "sg-eyebrow", style: "margin-top: 1.5rem") { "Marque" }
        div(class: "sg-grid") { BRAND.each { |name, var| swatch(name, var) } }
      end
    end

    def energy_section
      sg_section("Signature", "Palette par type d'énergie",
              "L'accent n'est pas une couleur unique : c'est le système de types du jeu. Les badges d'archétype en héritent.") do
        div(class: "sg-row") { ENERGIES.each { |label, type| energy_badge(label, type) } }
        div(class: "sg-grid") do
          ENERGIES.each { |label, type| swatch("#{label} / #{type}", "--#{Card::TYPE_TOKENS[type]}") }
        end
      end
    end

    def energy_badge(label, type)
      span(class: "badge badge-energy badge-#{type.downcase}") do
        span(class: "badge-pip")
        plain label
      end
    end

    def results_section
      sg_section("Sémantique", "Résultats de match",
              "Couleurs sémantiques, distinctes de l'accent. Rendues via le composant Ui::StatusBadge.") do
        div(class: "sg-row") do
          RESULTS.each { |status, label| render Ui::StatusBadge.new(status: status, label: label) }
        end
      end
    end

    def typography_section
      sg_section("Fondations", "Typographie",
              "Archivo (display), IBM Plex Sans (corps), IBM Plex Mono (données). Auto-hébergées en woff2.") do
        TYPE_SCALE.each do |tag, klass, sample|
          div(class: "sg-type-row") do
            span(class: "tag") { tag }
            span(class: klass) { sample }
          end
        end
      end
    end

    def buttons_section
      sg_section("Composants", "Boutons") do
        div(class: "sg-row") do
          render Ui::Button.new(label: "Importer un deck", variant: :primary, href: "#")
          render Ui::Button.new(label: "Comparer", variant: :secondary, href: "#")
          render Ui::Button.new(label: "Supprimer", variant: :danger, href: "#")
        end
      end
    end

    def badges_section
      sg_section("Composants", "Badges") do
        div(class: "sg-row") do
          span(class: "badge badge-format") { "Standard" }
          energy_badge("Charizard ex", "Fire")
          span(class: "badge badge-archetype") { "Archétype (repli sans type)" }
          span(class: "badge badge-warning") { "Proxies" }
        end
      end
    end

    def stats_section
      sg_section("Composants", "Statistiques", "Composant Ui::Stat — chiffres en Archivo tabulaire.") do
        div(class: "sg-row", style: "gap: 2.5rem") do
          render Ui::Stat.new(value: "68%", label: "Win rate")
          render Ui::Stat.new(value: "42", label: "Matchs")
          render Ui::Stat.new(value: "14", label: "Decks")
        end
      end
    end

    def form_section
      sg_section("Composants", "Champ de formulaire") do
        div(class: "sg-stack") do
          div(class: "form-group", style: "margin: 0") do
            label(class: "form-label", for: "sg-name") { "Nom du deck" }
            input(class: "form-input", id: "sg-name", type: "text", value: "Raging Bolt — Ogerpon")
            span(class: "form-hint") { "Auto-détecté depuis la liste importée." }
          end
        end
      end
    end

    def deck_card_section
      sg_section("Signature", "Carte de deck",
              "Bande de type en tête (dégradé si bi-type). Le vernis holo et la pastille ★ sont réservés aux decks « hot » — survole la seconde carte.") do
        div(class: "sg-deckdemo") do
          demo_deck("Charizard ex", "Charizard ex", "Fire",
                    "linear-gradient(90deg, var(--fire), var(--bolt))")
          demo_deck("Chien-Pao ex", "Chien-Pao / Baxcalibur", "Water",
                    "linear-gradient(90deg, var(--water), var(--psychic))", hot: "★ 72%")
        end
      end
    end

    def demo_deck(name, archetype, type, stripe, hot: nil)
      item_class = hot ? "deck-item is-foil" : "deck-item"
      div(class: item_class) do
        div(class: "deck-foil-sheen", aria_hidden: "true") if hot
        span(class: "deck-hot-flag") { hot } if hot
        div(class: "deck-stripe", style: "background: #{stripe}")
        div(class: "deck-item-link", style: "padding-left: 0") do
          h2(style: "padding-left: 0") { name }
          div(class: "deck-badges") do
            span(class: "badge badge-format") { "Standard" }
            energy_badge(archetype, type)
          end
          p(class: "deck-card-count") { "60 cards" }
        end
      end
    end

    def tokens_section
      sg_section("Tokens", "Élévation, rayons & espacement") do
        div(class: "sg-tokens") do
          %w[--e1 --e2 --e3].each_with_index do |var, i|
            label = [ "repos", "carte", "modale" ][i]
            code { var }
            div(class: "box", style: "box-shadow: var(#{var}); border: none")
            span { "élévation #{label}" }
          end
        end
        p(style: "margin-top: 1.25rem; color: var(--ink-500); font-size: 0.9rem") do
          plain "Rayons : 5px (contrôles), 8px (cartes), 12px (modales). "
          plain "Espacement sur un rythme de 4px (0.25 / 0.5 / 0.75 / 1 / 1.5 / 2 rem)."
        end
      end
    end
  end
end
