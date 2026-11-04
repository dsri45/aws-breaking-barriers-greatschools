import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "checkbox", "submit", "status", "clear"]
  static values = { chatId: String }

  get storageKey() {
    return `guided-search-comparison:${this.chatIdValue || "preview"}`
  }

  connect() {
    let selected = []
    try {
      const saved = JSON.parse(sessionStorage.getItem(this.storageKey))
      if (Array.isArray(saved)) selected = saved
    } catch {
      // Selection also works when browser storage is unavailable.
    }

    for (const checkbox of this.checkboxTargets) checkbox.checked = selected.includes(checkbox.value)
    this.update()
  }

  selectCard(event) {
    const card = event.target.closest("[data-school-comparison-target='card']")
    if (!card || event.target.closest("a, button, input, label, select, textarea, summary, details, form")) return

    this.toggle(card.dataset.schoolId)
  }

  keySelect(event) {
    if (!this.cardTargets.includes(event.target) || !["Enter", " "].includes(event.key)) return

    event.preventDefault()
    this.toggle(event.target.dataset.schoolId)
  }

  selectMap(event) {
    this.toggle(event.detail.schoolId)
  }

  selectMarker(event) {
    if (event.type === "keydown" && !["Enter", " "].includes(event.key)) return

    event.preventDefault()
    this.toggle(event.currentTarget.dataset.schoolId)
  }

  toggle(schoolId) {
    const checkbox = this.checkboxTargets.find(checkbox => checkbox.value === schoolId)
    if (!checkbox) return

    checkbox.checked = !checkbox.checked
    this.update()
  }

  clear() {
    for (const checkbox of this.checkboxTargets) checkbox.checked = false
    this.update()
  }

  update() {
    const ids = this.checkboxTargets.filter(checkbox => checkbox.checked).map(checkbox => checkbox.value)
    for (const card of this.cardTargets) {
      card.classList.toggle("is-comparing", ids.includes(card.dataset.schoolId))
    }
    for (const marker of this.element.querySelectorAll("[data-school-marker]")) {
      const selected = ids.includes(marker.dataset.schoolId)
      marker.classList.toggle("is-selected", selected)
      marker.setAttribute("aria-pressed", String(selected))
    }

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = ids.length < 2
      this.submitTarget.value = ids.length < 2 ? "Compare schools" : `Compare ${ids.length} schools`
      this.statusTarget.textContent = this.checkboxTargets.length < 2
        ? "Comparison needs at least two results."
        : ids.length ? `${ids.length} schools selected.` : "Select cards or map pins to compare."
    }
    if (this.hasClearTarget) this.clearTarget.hidden = ids.length === 0
    try {
      sessionStorage.setItem(this.storageKey, JSON.stringify(ids))
    } catch {
      // Current selections are already reflected in the form.
    }
    this.dispatch("selection", { detail: { ids } })
  }
}
