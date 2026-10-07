module Settings
  # How to search Cartodex from a Chromium browser's address bar. The engine is the ⌘K spotlight's
  # own endpoint opened as a page (SearchController), so what it answers is what the spotlight
  # answers. Where the one-time announcement (Ui::FlashMessages) links to.
  class SearchEngineSection < ApplicationComponent
    SHORTCUT = "cdx".freeze

    def view_template
      section(id: "search-engine", class: "settings-section") do
        h2 { "Browser search engine" }
        p(class: "settings-section-lead") do
          plain "Search your decks, cards, tournaments and archetypes from the address bar of " \
                "Chrome, Vivaldi or any Chromium-based browser — the same search as "
          # search-overlay rewrites every hint target to the platform's key: "Ctrl K" off a Mac.
          kbd(data: { search_overlay_target: "hint" }) { "⌘K" }
          plain "."
        end

        h3 { "Search URL" }
        code(id: "search-engine-url", class: "settings-reveal-value") { template_url }
        button(
          type: "button",
          class: "btn btn-secondary btn-sm",
          data: { controller: "clipboard", clipboard_text_value: template_url, action: "clipboard#copy" }
        ) { "Copy" }

        h3 { "Google Chrome" }
        ol(class: "settings-steps") do
          li do
            plain "Open "
            code { "chrome://settings/searchEngines" }
            plain ". If Cartodex is already listed under inactive shortcuts, click "
            strong { "Activate" }
            plain " and you are done."
          end
          li do
            plain "Otherwise, next to "
            strong { "Site search" }
            plain ", click "
            strong { "Add" }
            plain "."
          end
          li { fields_step("Shortcut") }
          li { usage_step }
        end

        h3 { "Vivaldi" }
        ol(class: "settings-steps") do
          li do
            plain "Open "
            code { "vivaldi://settings/search" }
            plain " and click "
            strong { "+" }
            plain " below the list of search engines."
          end
          li { fields_step("Nickname") }
          li { usage_step }
        end

        p(class: "settings-section-lead") do
          plain "Other Chromium browsers (Edge, Brave, Arc…) follow Chrome's steps under their own " \
                "search engine settings."
        end
      end
    end

    private

    # Concatenated, never passed to a URL helper as `q: "%s"`: the helper escapes it to %25s,
    # and a browser substitutes nothing into that.
    def template_url
      "#{search_url}?q=%s"
    end

    def fields_step(shortcut_label)
      plain "Name: "
      strong { "Cartodex" }
      plain " — #{shortcut_label}: "
      code { SHORTCUT }
      plain " — URL: the search URL above."
    end

    def usage_step
      plain "In the address bar, type "
      code { SHORTCUT }
      plain ", then Space or Tab, then your search."
    end
  end
end
