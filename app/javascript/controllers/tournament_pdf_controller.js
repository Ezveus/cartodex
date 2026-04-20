import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "profileSelect"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  download(event) {
    const deckId = event.currentTarget.dataset.tournamentPdfDeckIdValue
    const profileId = this.profileSelectTarget.value
    if (!profileId) return

    const url = `/decks/${deckId}/export?style=tournament_pdf&profile_id=${encodeURIComponent(profileId)}`
    window.location.href = url
    this.close()
  }
}
