import { Controller } from "@hotwired/stimulus"

let mapsReady
let mapsAuthError

function loadGoogleMaps(apiKey) {
  if (mapsAuthError) return Promise.reject(mapsAuthError)

  mapsReady ??= new Promise((resolve, reject) => {
    const script = document.createElement("script")
    const url = new URL("https://maps.googleapis.com/maps/api/js")
    url.search = new URLSearchParams({
      key: apiKey,
      loading: "async",
      v: "weekly",
      libraries: "marker",
      callback: "greatSchoolsGoogleMapsReady"
    })
    window.greatSchoolsGoogleMapsReady = () => resolve(window.google.maps)
    window.gm_authFailure = () => {
      mapsAuthError = new Error("Google Maps authentication failed")
      reject(mapsAuthError)
      document.dispatchEvent(new Event("google-maps:auth-failure"))
    }
    script.async = true
    script.src = url.href
    script.onerror = reject
    document.head.append(script)
  })
  return mapsReady
}

export default class extends Controller {
  static targets = ["canvas", "fallback"]
  static values = { apiKey: String, pins: Array, selectable: Boolean }

  async connect() {
    const render = this.render = Symbol()
    try {
      const maps = await loadGoogleMaps(this.apiKeyValue)
      if (this.render !== render) return

      const pins = this.pinsValue
      const center = pins[0] || { lat: 39.5, lng: -98.35 }
      const map = new maps.Map(this.canvasTarget, {
        center: { lat: center.lat, lng: center.lng },
        zoom: pins.length ? 14 : 4,
        mapId: "DEMO_MAP_ID"
      })
      const bounds = new maps.LatLngBounds()
      const { AdvancedMarkerElement } = maps.marker

      this.markers = pins.map(pin => {
        const { lat, lng, name, schoolId } = pin
        const position = { lat, lng }
        bounds.extend(position)
        const marker = new AdvancedMarkerElement({ map, position, title: name })
        const content = this.markerContent(pin)
        marker.append(content)
        return { marker, content, schoolId }
      })

      if (pins.some(({ lat, lng }) => lat !== center.lat || lng !== center.lng)) map.fitBounds(bounds, 40)
      this.canvasTarget.classList.remove("invisible")
      this.fallbackTarget.hidden = true
      this.dispatch("ready")
    } catch {
      if (this.render === render) this.reset()
    }
  }

  markerContent({ name, rating, schoolId }) {
    const selectable = this.selectableValue && schoolId
    const content = document.createElement(selectable ? "button" : "div")
    content.className = "gs-map-marker"
    content.title = name
    if (selectable) {
      content.type = "button"
      content.dataset.schoolId = schoolId
      content.dataset.schoolMarker = ""
      content.setAttribute("aria-label", `Compare ${name}`)
      content.setAttribute("aria-pressed", "false")
      content.addEventListener("click", event => {
        event.stopPropagation()
        this.dispatch("select", { detail: { schoolId } })
      })
    }

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("viewBox", "0 0 40 50")
    svg.setAttribute("aria-hidden", "true")
    const group = document.createElementNS(svg.namespaceURI, "g")
    group.setAttribute("transform", "translate(0 -4)")
    const path = document.createElementNS(svg.namespaceURI, "path")
    path.setAttribute("d", "M14.26 42.417C6.122 40.019.187 32.547.187 23.701.188 12.92 9.004 4.18 19.878 4.18S39.567 12.92 39.567 23.7c0 8.132-5.014 15.102-12.144 18.038l-6.767 11.575-6.397-10.897z")
    const circle = document.createElementNS(svg.namespaceURI, "circle")
    circle.setAttribute("cx", "20")
    circle.setAttribute("cy", "23.5")
    circle.setAttribute("r", "18")
    const text = document.createElementNS(svg.namespaceURI, "text")
    text.setAttribute("x", "20")
    text.setAttribute("y", "29")
    text.setAttribute("text-anchor", "middle")
    text.textContent = rating?.toString() ?? "–"
    group.append(path, circle, text)
    svg.append(group)
    content.append(svg)
    return content
  }

  selectionChanged({ detail: { ids } }) {
    for (const { marker, content, schoolId } of this.markers || []) {
      const selected = ids.includes(schoolId)
      content.classList.toggle("is-selected", selected)
      content.setAttribute("aria-pressed", String(selected))
      marker.zIndex = selected ? 1000 : 1
    }
  }

  disconnect() {
    this.reset()
  }

  reset() {
    this.render = null
    this.markers?.forEach(({ marker }) => { marker.map = null })
    this.markers = []
    if (this.hasCanvasTarget) {
      this.canvasTarget.classList.add("invisible")
      this.canvasTarget.replaceChildren()
    }
    if (this.hasFallbackTarget) this.fallbackTarget.hidden = false
  }
}
