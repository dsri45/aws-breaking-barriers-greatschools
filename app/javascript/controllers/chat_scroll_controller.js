import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const messages = this.messages
    const reply = messages?.querySelector("[data-guide-latest-response]")
    if (reply) messages.scrollTop = reply.offsetTop - messages.offsetTop
  }

  get messages() {
    return this.element.querySelector("#messages")
  }

  isChatForm(form) {
    return form instanceof HTMLFormElement && /\/api\/search(?:\.html)?$/.test(new URL(form.action).pathname)
  }

  guard(event) {
    if (this.pending && this.isChatForm(event.target)) event.preventDefault()
  }

  start(event) {
    const form = event.target
    if (!this.isChatForm(form) || !this.messages) return

    this.cancelScroll()
    const data = new FormData(form)
    this.pending = {
      follow: true,
      draft: form.querySelector("#follow_up_message")?.value,
      focus: !!form.closest("#chat-pane")
    }
    this.messages.querySelector(".guide-welcome")?.setAttribute("hidden", "")
    const bubble = document.createElement("div")
    bubble.className = "search-chat-message guide-pending-message"
    bubble.textContent = data.get("message")
    const status = document.createElement("div")
    status.className = "guide-thinking"
    status.setAttribute("role", "status")
    const dots = document.createElement("span")
    dots.className = "guide-thinking-dots"
    dots.setAttribute("aria-hidden", "true")
    for (let index = 0; index < 3; index++) dots.append(document.createElement("i"))
    const label = document.createElement("span")
    label.textContent = data.get("intent") ? "Looking more closely…" : "Checking school evidence…"
    status.append(dots, label)
    this.messages.append(bubble, status)
    this.messages.setAttribute("aria-busy", "true")
    const field = form.querySelector("#follow_up_message")
    if (field) field.readOnly = true
    this.scrollTo(status)
  }

  reading(event) {
    if (!this.pending || !this.messages?.contains(event.target)) return
    if (event.type === "wheel" && event.deltaY >= 0) return
    if (event.type === "keydown" && !["ArrowUp", "PageUp", "Home"].includes(event.key)) return

    this.pending.follow = false
    this.cancelScroll()
  }

  beforeRender(event) {
    if (event.target !== this.element || !this.messages) return

    this.cancelScroll()
    const messages = this.messages
    const top = messages.getBoundingClientRect().top
    const anchor = [...messages.querySelectorAll("[data-chat-message-key]")]
      .find(node => node.getBoundingClientRect().bottom > top)
    const snapshot = {
      top: messages.scrollTop,
      key: anchor?.dataset.chatMessageKey,
      offset: anchor ? anchor.getBoundingClientRect().top - top : 0
    }
    const pending = this.pending
    const render = event.detail.render
    event.detail.render = async (current, incoming) => {
      await render(current, incoming)
      const list = this.messages
      if (!list) return

      const same = [...list.querySelectorAll("[data-chat-message-key]")]
        .find(node => node.dataset.chatMessageKey === snapshot.key)
      list.scrollTop = same
        ? list.scrollTop + same.getBoundingClientRect().top - list.getBoundingClientRect().top - snapshot.offset
        : snapshot.top
      if (pending) {
        const failed = !!this.element.querySelector("[role='alert']")
        const field = this.element.querySelector("#follow_up_message")
        if (failed && field && pending.draft) field.value = pending.draft
        if (pending.focus && field && pending.follow) field.focus({ preventScroll: true })
        if (!failed && pending.follow) {
          const reply = list.querySelector("[data-guide-latest-response]")
          reply?.classList.add("guide-response-new")
          this.scrollFrame = requestAnimationFrame(() => {
            if (this.element.isConnected && this.messages === list && !this.pending) this.scrollTo(reply)
          })
        }
      }
      list.removeAttribute("aria-busy")
      this.pending = null
    }
  }

  finish({ target: form, detail: { success } }) {
    if (!this.isChatForm(form) || !this.pending || success) return

    this.messages?.querySelectorAll(".guide-pending-message, .guide-thinking").forEach(node => node.remove())
    this.messages?.removeAttribute("aria-busy")
    this.messages?.querySelector(".guide-welcome")?.removeAttribute("hidden")
    const field = form.querySelector("#follow_up_message")
    if (field) field.readOnly = false
    const error = document.createElement("p")
    error.className = "text-sm text-muted"
    error.setAttribute("role", "alert")
    error.textContent = "Your message couldn't be sent. Please try again."
    this.messages?.append(error)
    this.pending = null
  }

  scrollTo(node) {
    const list = this.messages
    if (!node || !list) return

    const top = list.scrollTop + node.getBoundingClientRect().top - list.getBoundingClientRect().top - 12
    list.scrollTo({ top, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" })
  }

  cancelScroll() {
    cancelAnimationFrame(this.scrollFrame)
    const list = this.messages
    if (list) list.scrollTo({ top: list.scrollTop, behavior: "instant" })
  }

  disconnect() {
    this.cancelScroll()
  }
}
