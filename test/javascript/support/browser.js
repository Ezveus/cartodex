import { vi } from "vitest"

// What jsdom does not implement and the controllers call. Installed once per test file by
// setup.js, as plain functions with no state of their own, so nothing leaks between tests; a test
// that wants to assert on one spies on it (`vi.spyOn(Element.prototype, "scrollIntoView")`), and
// restoreMocks puts the stand-in back.
//
// - <dialog>.showModal()/show()/close(): card_preview, search_overlay, result_modal,
//   tournament_pdf and share_modal open their dialogs this way. The stand-ins move `open` and fire
//   `close` the way a browser does; there is no top layer, no backdrop and no focus trap to test.
// - Element#scrollIntoView: dashboard_search and printing_picker. A no-op — jsdom lays nothing out.
export function installBrowserStandIns(window) {
  const dialog = window.HTMLDialogElement.prototype

  if (!dialog.showModal) {
    dialog.showModal = function () { this.open = true }
    dialog.show = function () { this.open = true }
    dialog.close = function (returnValue) {
      if (!this.open) return
      if (returnValue !== undefined) this.returnValue = returnValue
      this.open = false
      this.dispatchEvent(new window.Event("close"))
    }
  }

  if (!window.Element.prototype.scrollIntoView) window.Element.prototype.scrollIntoView = function () {}
}

// navigator.clipboard is left undefined by default, which is what a browser gives a non-secure
// origin and what clipboard_controller.js already handles. A test of the copying path stubs it:
//
//   const clipboard = stubClipboard()
//   …
//   expect(clipboard.writeText).toHaveBeenCalledWith("4 Pikachu SVI 1")
//
// `write` and a ClipboardItem that keeps its items cover deck_image_export_controller.js. Both are
// removed after the test.
export function stubClipboard() {
  const clipboard = { writeText: vi.fn(async () => {}), write: vi.fn(async () => {}) }
  Object.defineProperty(navigator, "clipboard", { value: clipboard, configurable: true })
  vi.stubGlobal("ClipboardItem", class { constructor(items) { this.items = items } })
  return clipboard
}

export function removeClipboard() {
  delete navigator.clipboard
}
