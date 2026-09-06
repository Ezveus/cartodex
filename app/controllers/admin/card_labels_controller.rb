module Admin
  # The card-label vocabulary, and the button that fills a `type` label from Limitless.
  #
  # No Pundit call anywhere below: Admin::BaseController#require_admin! is the whole gate for this
  # namespace, and an `authorize` here would be the only one in the panel.
  #
  # `role` labels are visible and editable but cannot be created, deleted, **or renamed** here:
  # they are seeded from `CardLabel::ROLES`, and CardLabels::RoleSuggester keys its rules on those
  # slugs. An invented role would be a label no rule can propose; a deleted one would take a rule's
  # output with it; and a *renamed* one is both at once — measured, an admin renaming `search` to
  # `deck-search` kept the human's decisions on the orphaned row, had the next db:seed recreate
  # `search` empty, had the suggester re-propose what the human had already decided, and left
  # /archetypes/:id rendering two sections both titled "Search". A `type` label is referenced by
  # nothing but its own search token, so its slug is ordinary data.
  class CardLabelsController < BaseController
    SEEDED_FAMILY_MESSAGE = "Role labels are seeded from the application, not created here.".freeze

    before_action :set_card_label, only: %i[edit update destroy import]

    def index
      # One grouped count rather than a per-row association read: the index prints a number per
      # row and loading every assignment to produce it is a payload nobody looks at.
      @card_labels = CardLabel.order(:family, :position, :slug)
      @assignment_counts = CardLabelAssignment.active.group(:card_label_id).count
    end

    def new
      @card_label = CardLabel.new(family: "type")
    end

    def create
      @card_label = CardLabel.new(card_label_params)
      return redirect_to(admin_card_labels_path, alert: SEEDED_FAMILY_MESSAGE) if @card_label.role?

      if @card_label.save
        redirect_to admin_card_labels_path, notice: "Card label created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      # `family` is not permitted (see card_label_params), so an edit cannot move a label between
      # the two governances — which is the only way the create refusal above could be walked round.
      if @card_label.update(card_label_params)
        redirect_to admin_card_labels_path, notice: "Card label updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      return redirect_to(admin_card_labels_path, alert: SEEDED_FAMILY_MESSAGE) if @card_label.role?

      count = @card_label.assignments.count
      @card_label.destroy
      redirect_to admin_card_labels_path,
        notice: "Card label deleted, with #{count} #{"assignment".pluralize(count)}."
    end

    def import
      unless @card_label.importable?
        redirect_to admin_card_labels_path,
          alert: "#{@card_label.name} has no search token, so there is nothing to import it from."
        return
      end

      import = current_user.imports.create!(
        kind: "card_labels",
        label: "#{@card_label.name} (#{@card_label.source_query})"
      )
      # Leading :: is load-bearing: this controller lives inside Admin, and Admin::CardLabels is
      # also this feature's Phlex namespace (Admin::CardLabels::IndexView etc.) — plain
      # CardLabels::ImportJob would resolve to that module first and raise NameError, since Ruby
      # constant lookup checks lexical scope before the top level.
      ::CardLabels::ImportJob.perform_later(import.id, @card_label.id, current_user.id)

      redirect_to admin_imports_path,
        notice: "Importing #{@card_label.name} from Limitless. Watch this table for the result."
    end

    private

    def set_card_label
      @card_label = CardLabel.find(params[:id])
    end

    # `family` is permitted on create alone, and `slug` on everything except a role update: see
    # #update and the note at the top of this file. Both are dropped rather than refused, because
    # the form does not offer either field for a role — a submitted one is a hand-made request.
    def card_label_params
      permitted = params.require(:card_label).permit(:slug, :name, :position, :description, :source_query)
      permitted[:family] = params[:card_label][:family] if action_name == "create"
      permitted.delete(:slug) if action_name == "update" && @card_label.role?
      permitted
    end
  end
end
