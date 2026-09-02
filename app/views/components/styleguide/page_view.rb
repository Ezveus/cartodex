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
        spotlight_section
        deck_card_section
        sharing_section
        printing_picker_section
        standard_pool_section
        settings_section
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
      sg_section("Composants", "Badges", "Deux rangées de badges, pas une seule : " \
              "Decks::ClassificationBadges (dont « Shared ») est réservé aux vues du " \
              "propriétaire ; Decks::PublicBadges — format et archétype seulement — est ce " \
              "qu'une surface publique montre.") do
        div(class: "sg-row") do
          span(class: "badge badge-format") { "Standard" }
          energy_badge("Charizard ex", "Fire")
          span(class: "badge badge-archetype") { "Archétype (repli sans type)" }
          span(class: "badge badge-warning") { "Proxies" }
          span(class: "badge") { "Shared" }
        end
        p(class: "sg-eyebrow", style: "margin-top: 1.5rem") { "Ui::ArchetypeBadge" }
        div(class: "sg-row") { render Ui::ArchetypeBadge.new(archetype: sg_sample_archetype) }
        p(class: "sg-eyebrow", style: "margin-top: 1.5rem") { "Decks::PublicBadges" }
        div(class: "sg-row") { render Decks::PublicBadges.new(deck: sg_sample_deck) }
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

    # Renders the real components with a hand-built Result, so the reference can't drift from the
    # spotlight the dashboard ships. The panel is forced open — on the dashboard, Stimulus opens it.
    #
    # ResultsList, not ResultsView: the latter wraps everything in turbo_frame_tag(FRAME_ID), and
    # Search::Spotlight above already put one of those on this page. Two elements with the same id
    # is the exact bug StyleguideControllerTest guards against for the MCP panels.
    def spotlight_section
      sg_section("Composants", "Recherche spotlight",
              "Champ de recherche du dashboard : panneau flottant, résultats groupés par type.") do
        div(class: "sg-spotlight-demo") do
          render Search::Spotlight.new
          div(class: "spotlight-panel spotlight-panel-open") do
            render Search::ResultsList.new(results: sg_spotlight_results)
          end
        end
      end
    end

    # Plain in-memory records (never persisted), like sg_settings_user_with_token above: this page
    # never touches the database. The keys are what the path helpers need (deck_path builds from
    # to_param, which reads key); nothing is saved.
    def sg_spotlight_results
      Search::Global::Result.new(
        query: "ogerpon",
        decks: [
          Deck.new(id: 1, key: "sg-ogerpon-toolbox", name: "Ogerpon Toolbox", format: "standard",
                   archetype: Archetype.new(name: "Teal Mask Ogerpon ex")),
          Deck.new(id: 2, key: "sg-tuesday-list", name: "Tuesday List", format: "glc")
        ],
        deck_total: 4,
        cards: [
          Card.new(id: 1, name: "Teal Mask Ogerpon ex", set_name: "TWM", set_number: "25"),
          Card.new(id: 2, name: "Ogerpon", set_name: "SVI", set_number: "211")
        ],
        card_total: 9,
        tournaments: [
          Tournament.new(id: 1, name: "Ogerpon Open", date: Date.new(2026, 4, 12), tier: "league_cup")
        ],
        tournament_total: 1,
        shared_decks: [
          Deck.new(id: 3, key: "sg-zoroark-box", name: "Zoroark Box", format: "standard",
                   archetype: Archetype.new(name: "Zoroark Control"))
        ],
        shared_deck_total: 1
      )
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

    # Ui::ArchetypeBadge and Decks::PublicBadges above render a sample deck outside a full share
    # flow; this section shows the flow itself — the form Decks::ShareFrame renders and the
    # readonly link it reveals once shared. Wrapped disabled/inert like the MCP token panels
    # below: the form posts to a real route, and the sample deck is not a row this page may
    # accidentally write to.
    def sharing_section
      sg_section("Composants", "Partage",
              "Decks::ShareFrame : le contenu du dialogue de partage, et ce que PATCH " \
              "/decks/:key/share re-rend une fois le deck partagé.") do
        settings_panel do
          render Decks::ShareFrame.new(deck: sg_sample_deck)
        end
      end
    end

    def sg_sample_archetype
      Archetype.new(name: "Charizard ex", primary_card: Card.new(type_symbol: "Fire"))
    end

    # Unpersisted, like every other stand-in on this page, but carries a key — the styleguide's
    # sample decks have done so since Stage 1, and both Decks::PublicBadges' link target and
    # Decks::ShareFrame's share_deck_path/deck_url need one to build from.
    def sg_sample_deck
      Deck.new(id: 99, key: "sg-share-sample", name: "Charizard ex — Pidgeot", format: "standard",
               shared: true, archetype: sg_sample_archetype)
    end

    def printing_picker_section
      sg_section("Composants", "Sélecteur d'impression",
              "Ligne set/numéro d'une carte de deck, là où une autre impression existe. Le menu, rempli à " \
              "l'ouverture depuis l'API, annote chaque impression et prévient avant que l'échange ne " \
              "transforme des exemplaires réels en proxies.") do
        div(class: "sg-printing-demo") do
          div(class: "deck-card-printing") do
            button(type: "button", class: "deck-card-set deck-card-set-swap", aria: { expanded: "true" }) { "ASC 16 ▾" }
            ul(class: "printing-picker-menu") do
              printing_option("ASC 16", "2 owned · 2 free", current: true)
              printing_option("JTG 56", "0 owned", warning: "⚠ 2 real copies become proxies")
              printing_option("PRE 4", "3 owned · 1 free · 1 already in deck")
            end
          end
        end
      end
    end

    # Rendered from the real component rather than from hand-written markup, unlike the
    # printing picker above: that one needs data the API supplies at runtime, whereas this one
    # needs only two pools and something that answers `persisted?`. Rendering the real thing is
    # what stops the styleguide drifting from it — and both branches are shown, because the
    # component chooses between them by comparing the pools' release dates and neither string
    # may name a record type.
    def standard_pool_section
      sg_section("Composants", "Ancre Standard périmée",
              "Standard tourne, et l'ancre d'un deck est épinglée : rien ne la déplace tout seul. " \
              "Ui::StandardPoolNotice est donc le seul moment où l'utilisateur apprend qu'un Standard " \
              "plus récent existe. Purement informatif — aucun champ n'est écrit.") do
        div(class: "sg-stack") do
          render Ui::StandardPoolNotice.new(
            record: notice_stand_in(pool(1, "TEF", "CRI", "2026-05-22")),
            expected: pool(2, "TEF", "PBL", "2026-07-17")
          )
          render Ui::StandardPoolNotice.new(
            record: notice_stand_in(pool(3, "TEF", "PBL", "2026-07-17")),
            expected: pool(4, "SVI", "PFL", "2025-11-14")
          )
        end
      end
    end

    def pool(id, first, last, released_on)
      StandardPool.new(
        id: id, released_on: released_on,
        first_card_set: CardSet.new(code: first), last_card_set: CardSet.new(code: last)
      )
    end

    # The notice refuses to render on an unsaved record — there is nothing to be stale about on
    # a creation form — so a plain Deck.new would show nothing here.
    def notice_stand_in(anchor)
      Struct.new(:standard_pool) do
        def persisted? = true
        def standard_pool_id = standard_pool.id
      end.new(anchor)
    end

    def printing_option(set, counts, current: false, warning: nil)
      li do
        button(
          type: "button",
          class: [ "printing-option", ("printing-option-current" if current) ].compact.join(" "),
          disabled: current
        ) do
          span(class: "printing-option-set") { set }
          span(class: "printing-option-counts") { counts }
          span(class: "printing-option-warning") { warning } if warning
        end
      end
    end

    # A 24-char placeholder in the shape of the real token (base58, no
    # spaces) — long enough to exercise the wrap/scroll behaviour without
    # ever being a value that could authenticate anything.
    PLACEHOLDER_TOKEN = "K7mQ2xVdN9wZaB4tRc6jHfLp".freeze

    def settings_section
      sg_section("Composants", "Jeton MCP",
              "Panneau de /settings : callout de révélation à fort contraste, paires libellé/valeur, " \
              "et wrap forcé sur le jeton et l'extrait de configuration.") do
        div(class: "sg-stack", style: "max-width: 640px; gap: 1.5rem") do
          # Both panels below point their forms at the real mcp_token_path.
          # Without this wrapper, clicking "Generate"/"Rotate"/"Revoke" here
          # would mutate the signed-in developer's actual MCP token. `disabled`
          # kills form submission and `inert` kills all pointer/keyboard
          # interaction (including the Copy button), while the markup still
          # renders exactly as it does on /settings.
          # Distinct dom_ids: two panels on one page would otherwise share the
          # `mcp-token` root id and the `lifetime` field id, so the second
          # panel's label would focus the first panel's select.
          settings_panel do
            render Settings::McpTokenSection.new(user: sg_settings_user_without_token, dom_id: "sg-mcp-token-empty")
          end
          settings_panel do
            render Settings::McpTokenSection.new(
              user: sg_settings_user_with_token, raw_token: PLACEHOLDER_TOKEN, dom_id: "sg-mcp-token-revealed"
            )
          end
          # Unpersisted user (id nil): the section's query can never match a
          # real Doorkeeper::AccessToken row, so this renders the empty state
          # without needing fixtures.
          settings_panel do
            render Settings::ConnectedAppsSection.new(user: sg_settings_user_without_token)
          end
        end
      end
    end

    def settings_panel(&block)
      fieldset(disabled: true, inert: true, style: "border: 0; margin: 0; padding: 0; min-width: 0", &block)
    end

    # Plain in-memory users (never persisted) so this page never touches the
    # database and can never leak a real token.
    def sg_settings_user_without_token
      User.new
    end

    def sg_settings_user_with_token
      User.new(
        api_token_digest: "placeholder-digest",
        api_token_created_at: 45.days.ago,
        api_token_expires_at: 45.days.from_now,
        api_token_last_used_at: 3.hours.ago
      )
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
