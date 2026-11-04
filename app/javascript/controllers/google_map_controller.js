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
  static values = { apiKey: String, pins: Array }

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
      const { AdvancedMarkerElement, PinElement } = maps.marker

      this.markers = pins.map(({ lat, lng, name, rating, kind }) => {
        const position = { lat, lng }
        bounds.extend(position)
        const marker = new AdvancedMarkerElement({ map, position, title: name })
        marker.append(new PinElement({
          background: kind === "selected" ? "#1F3B57" : "#4A86C5",
          glyphColor: "#fff",
          glyphText: rating?.toString() ?? "–"
        }))
        return marker
      })

      if (pins.some(({ lat, lng }) => lat !== center.lat || lng !== center.lng)) map.fitBounds(bounds, 40)
      this.canvasTarget.classList.remove("invisible")
      this.fallbackTarget.hidden = true
    } catch {
      if (this.render === render) this.reset()
    }
  }

  disconnect() {
    this.reset()
  }

  reset() {
    this.render = null
    this.markers?.forEach(marker => { marker.map = null })
    this.markers = []
    if (this.hasCanvasTarget) {
      this.canvasTarget.classList.add("invisible")
      this.canvasTarget.replaceChildren()
    }
    if (this.hasFallbackTarget) this.fallbackTarget.hidden = false
  }
}
