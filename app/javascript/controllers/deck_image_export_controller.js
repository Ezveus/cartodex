import { Controller } from "@hotwired/stimulus"

const CARD_WIDTH = 460
const CARD_HEIGHT = 640
const PADDING = 12
const MAX_COLS = 10

export default class extends Controller {
  async copy() {
    await this.withFeedback(async () => {
      const blob = await this.buildImage()
      await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })])
    })
  }

  async download() {
    await this.withFeedback(async () => {
      const blob = await this.buildImage()
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `${this.deckName()}.png`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
    })
  }

  async withFeedback(action) {
    const original = this.element.textContent
    this.element.textContent = "Generating..."
    this.element.disabled = true

    try {
      await action()
      this.element.textContent = "Done!"
    } catch (e) {
      console.error("Image export failed:", e)
      this.element.textContent = "Failed"
    }

    setTimeout(() => {
      this.element.textContent = original
      this.element.disabled = false
    }, 2000)
  }

  deckName() {
    const heading = document.querySelector(".deck-show-header h1")
    const name = heading?.textContent?.trim() || "deck"
    return name.replace(/[^a-z0-9\-_]+/gi, "_")
  }

  async buildImage() {
    const items = document.querySelectorAll(".deck-card-item")
    const cards = Array.from(items)
      .map(item => ({
        url: item.dataset.cardPreviewUrl,
        quantity: parseInt(item.querySelector(".deck-card-qty").textContent, 10)
      }))
      .filter(c => c.url && c.quantity > 0)

    if (cards.length === 0) throw new Error("No cards to export")

    const images = await Promise.all(cards.map(c => this.loadImage(c)))

    const cols = Math.min(MAX_COLS, images.length)
    const rows = Math.ceil(images.length / cols)

    const canvas = document.createElement("canvas")
    canvas.width = cols * CARD_WIDTH + (cols + 1) * PADDING
    canvas.height = rows * CARD_HEIGHT + (rows + 1) * PADDING

    const ctx = canvas.getContext("2d")
    ctx.fillStyle = "#f5f5f5"
    ctx.fillRect(0, 0, canvas.width, canvas.height)

    images.forEach((item, i) => {
      const col = i % cols
      const row = Math.floor(i / cols)
      const x = col * CARD_WIDTH + (col + 1) * PADDING
      const y = row * CARD_HEIGHT + (row + 1) * PADDING

      ctx.drawImage(item.img, x, y, CARD_WIDTH, CARD_HEIGHT)
      this.drawQuantityBadge(ctx, x, y, item.quantity)
    })

    return new Promise((resolve, reject) => {
      canvas.toBlob(blob => {
        if (blob) resolve(blob)
        else reject(new Error("Canvas export failed (likely CORS-tainted)"))
      }, "image/png")
    })
  }

  drawQuantityBadge(ctx, x, y, quantity) {
    const badgeW = 130
    const badgeH = 96
    const badgeR = 20
    const badgeMargin = 20
    const badgeX = x + CARD_WIDTH - badgeW - badgeMargin
    const badgeY = y + CARD_HEIGHT - badgeH - badgeMargin

    ctx.fillStyle = "rgba(0, 0, 0, 0.78)"
    this.roundRect(ctx, badgeX, badgeY, badgeW, badgeH, badgeR)
    ctx.fill()

    ctx.fillStyle = "white"
    ctx.font = "bold 64px system-ui, -apple-system, sans-serif"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText(`\u00D7${quantity}`, badgeX + badgeW / 2, badgeY + badgeH / 2)
  }

  roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.arcTo(x + w, y, x + w, y + h, r)
    ctx.arcTo(x + w, y + h, x, y + h, r)
    ctx.arcTo(x, y + h, x, y, r)
    ctx.arcTo(x, y, x + w, y, r)
    ctx.closePath()
  }

  loadImage(card) {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      img.onload = () => resolve({ ...card, img })
      img.onerror = () => reject(new Error(`Failed to load ${card.url}`))
      img.src = card.url
    })
  }
}
