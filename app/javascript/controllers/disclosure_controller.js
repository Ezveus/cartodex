import { Controller } from "@hotwired/stimulus"

// Opens and closes the element a button names in `aria-controls`. The state lives in the markup
// alone — `aria-expanded` on the button, `hidden` on the element — so deck_rows_controller.js can
// read which disclosures were open before it swaps a row and set them back afterwards.
export default class extends Controller {
  toggle({ currentTarget }) {
    const expanded = currentTarget.getAttribute("aria-expanded") === "true"
    currentTarget.setAttribute("aria-expanded", String(!expanded))

    const controlled = document.getElementById(currentTarget.getAttribute("aria-controls"))
    if (controlled) controlled.hidden = expanded
  }
}
