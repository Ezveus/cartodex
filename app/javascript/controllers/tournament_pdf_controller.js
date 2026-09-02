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
    const deckKey = event.currentTarget.dataset.tournamentPdfDeckKeyValue
    const profileId = this.profileSelectTarget.value
    if (!profileId) return

    const url = `/decks/${deckKey}/export?style=tournament_pdf&profile_id=${encodeURIComponent(profileId)}`
    window.location.href = url
    this.close()
  }
}
