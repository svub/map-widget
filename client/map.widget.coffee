Template.mapWidget.rendered = ->
  container = $ @find '.map-widget' # @firstNode
  unless _.isFunction d = @data then @data = -> d
  @controller = new MapController container, @data
  container.data 'mapController', @controller

defaultData = ->
  area: false
  areaType: 'circle'
  readOnly: false


class MapController
  constructor: (@container, @dataSource) ->
    @m = {}
    @wait = 100
    @minDistance = u.l.minRadius ? 1000
    @defaultDistance = u.l.defaultRadius ? 5000
    @maxDistance = u.l.maxRadius ? 500000
    @container = $ @container
    @doInit = _.once => @_doInit()
    if (d = @dataSource())?.autoInit ? true then @setData d
    Deps.autorun => @dataSource(); @update()

  setData: (newData, force=false) -> if force or not EJSON.equals newData, @data then @data = newData; @ensureInit =>
    @doNotify = false
    logmr 'MapWidget.setData', @data
    logmr 'MapWidget.setData merged', @data = _.extend defaultData(), @data
    @s = @data.show ? all: true
    if @data.readOnly then @s.form = false
    #@data.areaType ?= 'circle'

    # TODO initv2: instead of showing and hiding, remove and add components in init method
    @c.map.toggle      @s.all ? @s.map      ? true
    @c.search.toggle   @s.all ? @s.search   ? true
    @c.distance.toggle @s.all ? @s.distance ? true
    @c.current.toggle  @s.all ? @s.current  ? true
    @c.form.toggle     @s.form              ? true

    @container.attr 'style', @data.style?.container
    @c.map.attr 'style', @data.style?.mapContainer
    @d.map.attr 'style', @data.style?.map

    @plotMarkers() # to keep other markers behind marker
    if @s.marker ? @data.location? then @m.marker.addTo @m.map
    else @m.map.removeLayer @m.marker
    @updateLocation()
    later 50, => @doNotify = true

  setDistance: (d) ->
    d ?= @data.location?.distance ? @defaultDistance
    @d.distance.val Math.round (between d, @minDistance, @maxDistance)/1000
  isBbArea: -> @data.areaType is 'bounding-box'
  getDistance: ->
    if @isBbArea() then (u.l.distanceInMeters @m.map.getBounds())/2
    else between (unlessNaN (1000*parseFloat @d.distance.val()), @minDistance), @minDistance, @maxDistance
  getPosition: ->
    if @isBbArea() then @m.map.getBounds().getCenter()
    else @m.marker.getLatLng()
  getBoundingBox: (asArray = false) ->
    nesw = if @isBbArea() then [[(mb = @m.map.getBounds()).getNorth(), mb.getEast()],[mb.getSouth(), mb.getWest()]]
    else u.l.createBoundingBox (ll = @m.marker.getLatLng()).lat, ll.lng, @getDistance(), true
    if asArray then nesw
    else
      northEast: lat: nesw[0][0], lng: nesw[0][1]
      southWest: lat: nesw[1][0], lng: nesw[1][1]

  #setLocation: (location = @data.location, moveInView = false, calculateDistance = true) ->
  setLocation: (location, moveInView = false, calculateDistance = true) ->
    @data.location = location
    @updateLocation moveInView, calculateDistance, true
  updateLocation: (moveInView = false, calculateDistance = true, notify = false) ->
    logmr 'MapWidget.updateLocation: location', @data.location
    unless (location = u.l.sanitize @data.location)?
      if not @isBbArea() and @data.markers?.length and (b = L.latLngBounds (m.location for m in @data.markers))?
        logmr 'MapWidget.updateLocation: l from markers..., b', b
        logmr 'MapWidget.updateLocation: location', location = b.getCenter()
        bounds = [[b.getNorth(), b.getEast()], [b.getSouth(), b.getWest()]]
        logmr 'MapWidget.updateLocation: bounds', bounds
        @autoZoom true, bounds
      else
        @m.map.fitWorld()
      @updateArea false, false # hide area marker without location
    if calculateDistance and not @isBbArea() then @setDistance()
    @m.marker.setLatLng location ? [0,0]
    if @data.location?
      @updateArea moveInView, undefined, not @isBbArea()
    @updateSearch()
    if notify then @notify()
  moveLocation: (latLng, moveInView = false) ->
    if _.isBoolean latLng then [latLng, moveInView] = [undefined, latLng]
    if latLng? then @m.marker.setLatLng latLng
    else latLng = @m.marker.getLatLng()
    @updateArea moveInView
    @enrichLocation latLng
  # changed throttle to debounce so that map.zoom is updated
  enrichLocation: debounce 100, (latLng = @getPosition()) ->
    u.l.createFromPoint latLng.lat, latLng.lng, @getDistance(), @m.map.getZoom(), (location) =>
      # overwrite distance with current one so that the area does not jump when the enrichment finishes but the radius has changed in the meantime
      location.distance = @getDistance()
      _.extend location, @getBoundingBox()
      @setLocation location, false, false

  updateArea: (moveInView = false, area = @data.area, forceZoom = false) ->
    coordinates = @m.marker.getLatLng()
    distance = @getDistance()
    logm "MapWidget.updateArea moveInView=#{moveInView}; areaType=#{@data.areaType}; dist=#{distance}; coordinates", coordinates
    if area and not @isBbArea()
      #(if @data.areaType is 'rect' then @updateRectangle else @updateCircle).call @, coordinates, distance
      switch @data.areaType
        when 'rect' then @updateRectangle coordinates, distance
        when 'circle' then @updateCircle coordinates, distance
    else
      @m.map.removeLayer @m.rect
      @m.map.removeLayer @m.circle
    if (area and not @isBbArea()) or forceZoom
      later 10, => @autoZoom moveInView, coordinates, distance
  updateRectangle: (coordinates, distance) ->
    @m.rect.setBounds bounds = u.l.createBoundingBox(coordinates.lat, coordinates.lng, distance, true)
    @m.rect.addTo @m.map

  updateCircle: (coordinates, distance) ->
    @m.circle.setLatLng coordinates
    @m.circle.setRadius distance
    @m.circle.addTo @m.map

  updateSearch: debounce 300, ->
    # u.w.setTypeaheadQuery @d.search, (@data.location?.label ? '')), 300
    logmr 'MapWidget.updateSearch: l, m.search', @data.location, @m.search
    @m.search.setValue @data.location

  #updateSize: (repeat = 1) -> # call when map does not fit container, e.g. after container resizing
  #  log 'MapWidget.updateSize...'
  #  try @m.map._onResize()
  #  try @m.map.panBy [0,1]; @m.map.panBy [0,-1]
  #  if repeat > 1 then later 50, => @updateSize repeat-1

  updateSize: (repeat = 1) -> # call when map does not fit container, e.g. after resizing
    log 'MapWidget.updateSize...'
    try @m.map.invalidateSize()
    if repeat > 1 then later 50, => @updateSize repeat-1

  update: (repeat = 1) -> # force updating: reload data, reinit map view
    later  5, => try @updateSize repeat
    later 15, => try @setData @dataSource(), true

  # coordinates can be bounds array, too
  autoZoom: (zoom = false, coordinates = @m.marker.getLatLng(), distance = @getDistance()) ->
      #bounds = if (_.isArray coordinates) then coordinates
      #else u.l.createBoundingBox coordinates.lat, coordinates.lng, distance*1.1, true
      if @isBbArea()
        bounds = if (l = @data.location).northEast? and l.southWest?
          L.latLngBounds l.southWest, l.northEast
        else L.latLngBounds u.l.createBoundingBox l, true
        logmr 'MapWidget.autoZoom: l, b', l, bounds
        try @m.map.fitBounds bounds
      else
        bounds = if (_.isArray coordinates) then coordinates
        else u.l.createBoundingBox coordinates.lat, coordinates.lng, distance*1.1, true
        logmr 'MapWidget.autoZoom: coords, z, d, b', coordinates, zoom, distance, bounds
        if (mapBounds = @m.map.getBounds()).contains bounds # zoom in?
          logmr 'MapWidget.autoZoom: zoom in', mapBounds.toBBoxString()
          if distance * 5 < u.l.distanceInMeters mapBounds # much smaller, zoom in
            try @m.map.fitBounds bounds
        else # zoom out?
          logmr 'MapWidget.autoZoom: zoom out', mapBounds.toBBoxString()
          boundsMuchBigger = not @m.map.getBounds().pad(2).contains bounds
          logmr 'MapWidget.autoZoom: bounds, muchBigger', bounds, boundsMuchBigger
          if zoom or boundsMuchBigger then @m.map.fitBounds bounds
          else @m.map.panTo coordinates

      later 2, =>
        logmr 'MapWidget.autoZoom: new bounds', @m.map.getBounds().toBBoxString()

  plotMarkers: ->
    if @m.markers?.length
      @m.map.removeLayer m for m in _.flatten @m.markers
    @m.markers = unless @data.markers?.length then []
    else @plotMarker index, def for def, index in @data.markers
  plotMarker: (index, def) ->
    markerHtml = '<i class="fa fa-map-marker fa-stack-2x"></i><i class="fa fa-circle fa-stack-1x"></i><span>'+(index+1)+'</span>'
    icon = L.divIcon
      className:  'result-map-marker'+(if index>8 then ' more-than-one-digit' else '')
      iconAnchor: [8.666, 29]
      html:       markerHtml
    ($ icon).data 'placement', 'left'
    marker = L.marker def.location,
      icon: icon
      title: def.label
    u.events marker, def.events
    if def.popup?
      popupDomEl = $ "<div>#{def.popup}</div>" # needed to assign click event
      marker.bindPopup popupDomEl[0]
      if def.popupClick? then popupDomEl.on 'click', def.popupClick
    #if def.popup?
    #  marker.bindPopup def.popup
    #  marker.on 'click', -> @m.map.openPopup marker.bindPopup def.popup
    marker.addTo @m.map
    if def.area
      circle = (L.circle def.location, def.location.distance, { color: u.activityAreaColor, stroke: false })
      circle.addTo @m.map
      [marker, circle]
    else marker

  # wait this long to overcome wait between first click until spinner keeps changing numbers quickly; before 200 caused
  # that...
  distanceChangedUpdateLocationAfter: debounce 100, -> @moveLocation true
  distanceChangedUpdateLocationDuring: throttle 5000, -> @moveLocation true
  distanceChangedUpdateArea: throttle 100, -> @updateArea false
  mapClicked: (event) ->
    n=(b=@m.map.getBounds()).getNorth();s=b.getSouth();w=b.getWest();e=b.getEast()
    width = u.l.distanceInMeters n, e, n, w
    height = u.l.distanceInMeters n, e, s, e
    if not @isBbArea() then @setDistance .45 * Math.min width, height
    @moveLocation event.latlng
  geoLocationClicked: ->
    #@d.currentLocation.addClass 'active'
    @busy true
    u.x.currentLocation (location) =>
      @setLocation location, true
      #later 10, => @d.currentLocation.removeClass 'active'
      later 10, => @busy false
  notify: -> if @doNotify and @data.onChange? then @runNotify()
  runNotify: debounce 500, ->
    (l = @data.location)?.distance = distance = @getDistance()
    @data.onChange l, distance

  ensureInit: (done) ->
    # TODO initv2: wait if map is needed only
    unless L?
      later (@wait*=2), => @ensureInit(done)
      return
    @doInit()
    done()
  busyTimeout: u.debounce 5000, -> @busy false
  busy: (isBusy = false) ->
    @m.spinner.toggle isBusy
    if isBusy then @busyTimeout()

  _doInit: ->
    # TODO initv2: remove once; instead, add and remove components as configured
    # get references
    @c = # conainters
      map: $ '.map-container', @container
      search: $ '.search-container', @container
      distance: $ '.distance-container', @container
      current: $ '.current-container', @container
      form: $ '.manipulation-form', @container
    @d = # data object
      map: $ '.map', @c.map
      search: $ '.search', @c.search
      distance: $ '.distance', @c.distance
      currentLocation: $ '.current-location', @c.current
    # @m.search = u.w.createLocationTypeahead @d.search, @data.location?.label, ((event, location) => @setLocation location, true), => @data.location
    @m.spinner = ($ '.fa-spinner', @container).hide()
    onSelectL = (event, location) => @setLocation location, true
    initL = => @data.location
    @m.search = u.w.createLocationTypeahead @d.search, onSelectL, initL, (isBusy) => @busy isBusy
    #@m.search.addClear? showOnLoad: true, top: null, right: null, onClear: => @setLocation null, true
    # init leaflet map and layers
    unless @d.map?.length then @c.map.empty().append(@d.map = $ '<div class="map"></div>')
    unless (@m.map = @d.map.data 'leafletMap')?
      @m.map = map = L.map @d.map[0],
        center: @data?.location ? [0,0]
        zoom: 13
      # add an OpenStreetMap tile layer
      L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', { attribution: '&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors'}).addTo map
      @d.map.data 'leafletMap', map
      @m.rect = (L.rectangle [[0,0],[0,0]], { color: u.pickLocationRectColor, weight: 1 })
      @m.circle = (L.circle [0,0], 0, { color: u.pickLocationRectColor, weight: 1 })
      @m.marker = L.marker [0, 0], title: 'current location', zIndexOffset: 1

    # hook up event handlers
    areaChanged = =>
      @distanceChangedUpdateLocationDuring()
      @distanceChangedUpdateLocationAfter()
      @distanceChangedUpdateArea()
    #@d.distance.on 'change', => @distanceChanged()
    unless @data.readOnly
      @d.distance.on 'change', -> areaChanged()
      @m.map.on 'zoomend', =>
        log '$$$$$$$'
        if @isBbArea() then log '########'; areaChanged()
      @m.map.on 'click', (e) => @mapClicked e
      @d.currentLocation.on 'click', => @geoLocationClicked()

