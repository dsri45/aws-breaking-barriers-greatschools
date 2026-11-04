import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  fill({ params: { message } }) {
    const field = this.element.querySelector("#follow_up_message")
    field.value = message
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.focus()
    field.setSelectionRange(field.value.length, field.value.length)
  }

  priorities() {
    const field = document.querySelector("#need, .search-priorities button")
    field?.focus()
  }
}
