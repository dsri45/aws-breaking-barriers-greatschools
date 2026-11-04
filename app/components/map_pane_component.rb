# Renders the Google map when configured and supplies the SVG preview otherwise.
class MapPaneComponent < ViewComponent::Base
  WIDTH = 380
  HEIGHT = 720
  PAD = 70

  Point = Data.define(:pin, :x, :y)

  def initialize(pins:)
    @pins = pins
  end

  def google_maps_key = ENV["GOOGLE_MAPS_API_KEY"].presence

  def google_maps_pins
    @pins.map do |pin|
      { lat: pin.lat, lng: pin.lon, name: pin.name, rating: pin.rating, kind: pin.kind }
    end
  end

  def points
    return [] if @pins.empty?

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
