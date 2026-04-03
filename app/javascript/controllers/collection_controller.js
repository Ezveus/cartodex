import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count", "scannerModal", "video"]

  connect() {
    this.loadCollectionCount()
  }

  async loadCollectionCount() {
    try {
      const response = await fetch('/api/collections')
      const data = await response.json()
      this.countTarget.textContent = data.total_cards || 0
    } catch (error) {
      console.error('Error loading collection count:', error)
    }
  }

  async view() {
    // Will be implemented with collection view
  }

  async openScanner() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
      this.videoTarget.srcObject = stream
      await this.videoTarget.play()
      this.scannerModalTarget.style.display = 'block'
      this.startScanning()
    } catch (error) {
      console.error('Error accessing camera:', error)
      alert('Could not access camera. Please ensure you have granted camera permissions.')
    }
  }

  closeScanner() {
    if (this.videoTarget.srcObject) {
      const tracks = this.videoTarget.srcObject.getTracks()
      tracks.forEach(track => track.stop())
    }
    this.scannerModalTarget.style.display = 'none'
  }

  startScanning() {
    // Will implement card detection logic here
    // This will use a card recognition service to identify Pokemon cards
    // For now, this is a placeholder
  }

  // Helper method to make authenticated API requests
  async fetchWithToken(url, options = {}) {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const defaultOptions = {
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': token
      },
      credentials: 'same-origin'
    }

    return fetch(url, { ...defaultOptions, ...options })
  }
}
