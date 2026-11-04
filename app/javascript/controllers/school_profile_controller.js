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
    this.observer?.disconnect()
  }

  select(event) {
    this.activate(event.currentTarget.hash)
  }

  activate(hash) {
    for (const link of this.navLinkTargets) {
      if (link.hash === hash) {
        link.setAttribute("aria-current", "location")
        this.revealNavLink(link)
      } else link.removeAttribute("aria-current")
    }
  }

  revealNavLink(link) {
    const scroller = link.parentElement
    const bounds = scroller.getBoundingClientRect()
    const target = link.getBoundingClientRect()
    const delta = target.left < bounds.left ? target.left - bounds.left - 12
      : target.right > bounds.right ? target.right - bounds.right + 12 : 0
    if (delta) scroller.scrollBy({ left: delta,
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" })
  }
}
