import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["navLink"]

  connect() {
    this.activate(window.location.hash || "#overview")
    this.observer = new IntersectionObserver(entries => {
      const entry = entries.find(entry => entry.isIntersecting)
      if (entry) this.activate(`#${entry.target.id}`)
    }, { rootMargin: "-140px 0px -60% 0px" })

    for (const link of this.navLinkTargets) {
      const section = this.element.querySelector(link.hash)
      if (section) this.observer.observe(section)
    }
  }

  disconnect() {
    this.observer.disconnect()
  }

  select(event) {
    this.activate(event.currentTarget.hash)
  }

  activate(hash) {
    for (const link of this.navLinkTargets) {
      if (link.hash === hash) link.setAttribute("aria-current", "location")
      else link.removeAttribute("aria-current")
    }
  }
}
