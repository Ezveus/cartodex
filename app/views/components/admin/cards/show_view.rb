module Admin
  module Cards
    class ShowView < ApplicationComponent
      def initialize(card:)
        @card = card
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "#{@card.name} — #{@card.set_name} #{@card.set_number}") do
            div(class: "admin-header-actions") do
              link_to "Edit", helpers.edit_admin_card_path(@card), class: "btn btn-secondary"
              link_to "Rescrape", helpers.rescrape_admin_card_path(@card),
                data: { turbo_method: :post, turbo_confirm: "Rescrape #{@card.name} from Limitless?" },
                class: "btn btn-primary"
            end
          end

          div(class: "admin-grid-2col") do
            div do
              if @card.image_url.present?
                image_tag @card.image_url, alt: @card.name, style: "width: 300px; border-radius: 12px;"
              end
            end
            div do
              table(class: "admin-table") do
                tbody do
                  info_row("Type", @card.card_type)
                  info_row("HP", @card.hp)
                  info_row("Energy Type", @card.type_symbol)
                  info_row("Rarity", @card.rarity)
                  info_row("Set", "#{@card.set_full_name} (#{@card.set_name} #{@card.set_number})")
                  tr do
                    td { strong { "Fingerprint" } }
                    td { code { @card.fingerprint } }
                  end
                  tr do
                    td { strong { "Card Set" } }
                    td do
                      if @card.card_set
                        link_to @card.card_set.name, helpers.admin_card_set_path(@card.card_set)
                      else
                        plain "\u2014"
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      private

      def info_row(label, value)
        tr do
          td { strong { label } }
          td { value.to_s }
        end
      end
    end
  end
end
