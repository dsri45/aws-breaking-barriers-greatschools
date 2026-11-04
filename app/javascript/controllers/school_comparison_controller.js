import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "submit", "status"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasSubmitTarget) return

    const count = this.checkboxTargets.filter(checkbox => checkbox.checked).length
    this.submitTarget.disabled = count < 2
    this.submitTarget.value = count < 2 ? "Compare schools" : `Compare ${count} schools`
    this.statusTarget.textContent = this.checkboxTargets.length < 2
      ? "Comparison needs at least two results."
      : count < 2 ? "Select at least two schools." : `${count} schools selected.`
  }
}
