---
name: phlex-architecture
description: Phlex component architecture guide for this Rails app. Always loaded — provides conventions, component hierarchy, and patterns for building views. All views use Phlex components; never write ERB view logic.
autoload: true
---

# Phlex Component Architecture

This app uses **Phlex 2.4** (phlex-rails ~> 2.2) for all views. ERB files exist only as one-liner wrappers that delegate to Phlex components.

## Core Rule

**Never write view logic in ERB.** Always create or modify Phlex components. ERB templates should contain only:

```erb
<%= render Cards::IndexView.new(blocks: @blocks, current_set: @current_set, cards: @cards) %>
```

## Component Hierarchy

All components live under `app/views/components/`.

### Base Class

`ApplicationComponent < Phlex::HTML` — includes Rails helpers:
- Routes, LinkTo, FormWith, ButtonTo, ContentFor, Flash
- ImageTag, NumberToCurrency, TurboStreamFrom, CollectionSelect
- `delegate_missing_to :helpers` as fallback for any other Rails helper

### Layouts

Include `Phlex::Rails::Layout` for full HTML document rendering. Controllers reference them via:

```ruby
layout -> { Layouts::ApplicationLayout }
```

| Class | Used by |
|---|---|
| `Layouts::ApplicationLayout` | `ApplicationController` (all app pages) |
| `Layouts::AdminLayout` | `Admin::BaseController` (admin pages) |

### UI Components (reusable)

Under `app/views/components/ui/`. Use these to avoid duplication:

| Component | Purpose |
|---|---|
| `Ui::Navbar` | App and admin navbars (parameterized via `variant:`) |
| `Ui::StatCard` | Value + label card (admin dashboard, deck stats) |
| `Ui::PageHeader` | Title + optional action buttons |
| `Ui::AdminTable` | Table with column headers, yields rows block |
| `Ui::DeckImport` | Deck import modal + importing section (shared by dashboard and decks index) |
| `Ui::Card` | Generic card wrapper |
| `Ui::Button` | Button/link with variant support |
| `Ui::FormGroup` | Label + field + errors wrapper |
| `Ui::TextInput` | Styled text input |
| `Ui::FormErrors` | Model error display |
| `Ui::FlashMessages` | Flash notice/alert display |
| `Ui::AuthLinks` | Sign in / sign up / forgot password links |

### View Components (page-level)

Naming convention: `{Namespace}::{Action}View`

```
Home::WelcomeView, Home::DashboardView
Cards::IndexView, Cards::ShowView
Decks::IndexView, Decks::ShowView, Decks::NewView
Admin::Dashboard::IndexView
Admin::CardSets::IndexView, ShowView, NewView, EditView, Form
Admin::Cards::IndexView, ShowView, EditView
Admin::Users::IndexView
Admin::Decks::IndexView, ShowView
Devise::Sessions::NewView, etc.
```

## Key Patterns

### Stimulus Data Attributes

Phlex converts underscores to hyphens in data attribute keys automatically:

```ruby
div(data: { controller: "card-preview" }) do
  li(data: {
    action: "mouseenter->card-preview#show",
    card_preview_target: "item",          # → data-card-preview-target="item"
    deck_card_quantity_value: dc.quantity  # → data-deck-card-quantity-value="..."
  })
end
```

### Forms

`form_with` works inside Phlex blocks. Form builder methods (`f.text_field`, `f.select`, etc.) return HTML that phlex-rails handles automatically:

```ruby
form_with(model: @deck, class: "deck-form") do |f|
  div(class: "form-group") do
    f.label :name, class: "form-label"
    f.text_field :name, class: "form-input"
  end
end
```

For `text_field_tag` / `submit_tag`, access via `helpers.text_field_tag`.

### Conditional CSS Classes

`tokens()` is **not available** in Phlex 2.4. Use array + compact + join:

```ruby
# Correct
nav(class: [ "navbar", ("admin-navbar" if @variant == :admin) ].compact.join(" "))

# Also correct for single conditional
li(class: ("active" if @current_set == card_set))
```

### Avoid `raw()`

Phlex 2.4 rejects unsafe objects passed to `raw()`. Instead of passing HTML strings, use Phlex markup methods:

```ruby
# Wrong — will raise Phlex::ArgumentError
p { raw("<strong>#{value}</strong>") }

# Correct
p do
  strong { value }
end
```

### Accessing Rails Helpers

Most helpers are included explicitly on `ApplicationComponent`. For anything not included, use `helpers.method_name`:

```ruby
helpers.current_user
helpers.user_signed_in?
helpers.controller_name
```

### Creating a New View

1. Create the component in `app/views/components/{namespace}/{action}_view.rb`
2. Inherit from `ApplicationComponent`
3. Accept instance variables as constructor params
4. Update the ERB wrapper to render the component
5. Reuse existing `Ui::` components wherever possible
