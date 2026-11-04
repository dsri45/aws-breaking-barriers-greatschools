import { Controller } from "@hotwired/stimulus"

const minimums = { chat: 240, map: 240 }
const defaults = { chat: 360, map: 380 }
const minimumResultsWidth = 340
const storageKey = "guided-search-pane-widths"

export default class extends Controller {
  static targets = ["separator"]

  connect() {
    this.widths = { ...defaults }
    try {
      const saved = JSON.parse(sessionStorage.getItem(storageKey))
      for (const pane of Object.keys(defaults)) {
        if (Number.isFinite(saved?.[pane])) this.widths[pane] = saved[pane]
      }
    } catch {
      // Panel resizing still works when storage is unavailable.
    }

    this.observer = new ResizeObserver(() => this.layout())
    this.observer.observe(this.element)
    this.layout()
  }

  disconnect() {
    this.observer.disconnect()
  }

  start(event) {
    if (!event.isPrimary || event.button !== 0) return

    const handle = event.currentTarget
    const pane = handle.dataset.pane
    handle.focus({ preventScroll: true })
    handle.setPointerCapture(event.pointerId)
    this.drag = { pane, origin: event.clientX, width: this.visibleWidths[pane] }
  }

  resize(event) {
    if (!this.drag || !event.currentTarget.hasPointerCapture(event.pointerId)) return

    const { pane, origin, width } = this.drag
    this.setWidth(pane, width + (event.clientX - origin) * this.direction(pane))
  }

  stop() {
    this.drag = null
  }

  nudge(event) {
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return

    event.preventDefault()
    const pane = event.currentTarget.dataset.pane
    const step = event.key === "ArrowRight" ? 24 : -24
    this.setWidth(pane, this.visibleWidths[pane] + step * this.direction(pane))
  }

  direction(pane) {
    return pane === "chat" ? 1 : -1
  }

  availableWidth() {
    const handleWidth = this.separatorTargets.reduce((width, handle) => width + handle.offsetWidth, 0)
    return this.element.clientWidth - minimumResultsWidth - handleWidth
  }

  layout() {
    const available = this.availableWidth()
    const chat = this.clamp("chat", this.widths.chat, available - minimums.map)
    const map = this.clamp("map", this.widths.map, available - chat)
    this.visibleWidths = { chat, map }
    for (const handle of this.separatorTargets) {
      const pane = handle.dataset.pane
      const other = pane === "chat" ? "map" : "chat"
      this.element.style.setProperty(`--${pane}-width`, `${this.visibleWidths[pane]}px`)
      handle.setAttribute("aria-valuemin", minimums[pane])
      handle.setAttribute("aria-valuemax", Math.max(minimums[pane], available - this.visibleWidths[other]))
      handle.setAttribute("aria-valuenow", this.visibleWidths[pane])
    }
  }

  setWidth(pane, width) {
    const other = pane === "chat" ? "map" : "chat"
    this.widths = { ...this.visibleWidths, [pane]: this.clamp(pane, width, this.availableWidth() - this.visibleWidths[other]) }
    this.layout()
    try {
      sessionStorage.setItem(storageKey, JSON.stringify(this.widths))
    } catch {
      // The current panel sizes are already applied.
    }
  }

  clamp(pane, width, max) {
    return Math.max(minimums[pane], Math.min(width, max))
  }
}
