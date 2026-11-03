# Map placeholder: projects result coordinates into the pane and draws
# GreatSchools-style rating pins. Swap the background for an Amazon Location
# Service map (MapLibre GL JS) on day 2; the pin data stays the same.
class MapPaneComponent < ViewComponent::Base
  WIDTH = 380
  HEIGHT = 720
  PAD = 70

  Point = Data.define(:pin, :x, :y)

  def initialize(pins:)
    @pins = pins
  end

  def points
    lats = @pins.map(&:lat)
    lons = @pins.map(&:lon)
    lat_span = [ lats.max - lats.min, 0.001 ].max
    lon_span = [ lons.max - lons.min, 0.001 ].max
    @pins.map do |pin|
      x = PAD + (pin.lon - lons.min) / lon_span * (WIDTH - 2 * PAD)
      y = PAD + (lats.max - pin.lat) / lat_span * (HEIGHT - 2 * PAD - 120)
      Point.new(pin:, x: x.round, y: y.round)
    end.sort_by { |pt| pt.pin.kind == :selected ? 1 : 0 } # selected pin on top
  end

  def label(pin) = pin.rating ? pin.rating.to_s : "–"
end
