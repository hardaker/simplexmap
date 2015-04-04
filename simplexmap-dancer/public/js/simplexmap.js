function createmap(lat, lon, repeaters, stations, links, simplexes) {
	var currentLine;
	var self = {};

	var allStations = stations;
	var allRepeaters = repeaters;

	// create the map 
	var map = L.map('map', {
		center: [lat, lon],
		zoom:   10,
	});

	// add the base map
	L.tileLayer('http://a.tiles.mapbox.com/v3/hardaker.kc8b5joe/{z}/{x}/{y}.png', {
		attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors, <a href="http://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
		maxZoom: 18
	}).addTo(map);

	var iconBaseSize 	= 24;
	var iconHomeSize 	= 2 * iconBaseSize/3;
	var iconRepeaterSize = iconBaseSize;

	// create the icons
	var homeIcon = L.icon({
		iconUrl: '/icons/building-24@2x.png',
		iconSize:   [iconHomeSize,   iconHomeSize],
		iconAnchor: [iconHomeSize/2, iconHomeSize],
		popupAnchor: [iconHomeSize/2, -100],
	});

	var repeaterIcon = L.icon({
		iconUrl: '/icons/triangle-24@2x.png',
		iconSize:   [iconRepeaterSize,   iconRepeaterSize],
		iconAnchor: [iconRepeaterSize/2, iconRepeaterSize],
		popupAnchor: [iconRepeaterSize/2, -100],
	});
	
	// setup the repeater grouping
	var repeaterLayerObjs = [];
	var repeaterLines = [];
	for (repeater in repeaters) {
		if (repeaters.hasOwnProperty(repeater)) {
			repeaters[repeater]['title']  =
				"<strong><a href=\"/repeaters/" + repeaters[repeater]['repeaterid'] + "\">" +
				repeaters[repeater]['repeatername'] + "</a></strong><br />" +
				repeaters[repeater]['repeatercallsign'] + "<br />" +
				repeaters[repeater]['repeaterfreq'] + " / " +
				repeaters[repeater]['repeateroffset'] +
				(repeaters[repeater]['repeaterpl'] ? (" PL: " + repeaters[repeater]['repeaterpl']) : "") +
				(repeaters[repeater]['repeaterdcs'] ? (" DCS: " + repeaters[repeater]['repeaterdcs']) : "") + "<br />"
			;
			repeaters[repeater]['offset'] = [0, -iconRepeaterSize/2];

			var repeatMark = 
				L.marker([parseFloat(repeaters[repeater]['repeaterlat']),
						  parseFloat(repeaters[repeater]['repeaterlon'])],
						 {title: repeaters[repeater]['repeatercallsign'],
						  icon: repeaterIcon});

			repeaterLayerObjs.push(repeatMark);

			repeaters[repeater]['lines'] = [];
			repeaters[repeater]['mark'] = repeatMark;
			repeatMark['ws6z_lines'] = [];
			repeatMark['ws6z_shown'] = false;
			repeatMark['ws6z_obj'] = repeaters[repeater];
			repeatMark.on('click', onMarkerClick);
		}
	}			 
	var repeaterGroup = L.layerGroup(repeaterLayerObjs);
	repeaterGroup.addTo(map);

	// set up the station grouping
	var stationLayerObjs = [];
	var stationLines = [];
	for (station in stations) {
		if (stations.hasOwnProperty(station)) {
			stations[station]['title'] =
				"<strong><a href=\"/stations/" + stations[station]['locationid'] + "\">" +
				stations[station]['callsign'] + ": " +
				stations[station]['locationname'] + "</a></strong>;

			stations[station]['offset'] = [0, -iconHomeSize/2];

			var stationMark = 
				L.marker([parseFloat(stations[station]['locationlat']),
						  parseFloat(stations[station]['locationlon'])],
						 {title: stations[station]['callsign'] + " / " + stations[station]['locationname'],
						  icon: homeIcon}).addTo(map)
			stationLayerObjs.push(stationMark);

			stations[station]['lines'] = [];
			stations[station]['mark'] = stationMark;
			stationMark['ws6z_lines'] = [];
			stationMark['ws6z_shown'] = false;
			stationMark['ws6z_obj'] = stations[station];
			stationMark.on('click', onMarkerClick);
		}
	}
	var stationGroup = L.layerGroup(stationLayerObjs);
	stationGroup.addTo(map);

	// add the links between the stations and the repeaters
	for (linkid in links) {
		if (links.hasOwnProperty(linkid)) {
			var link = links[linkid];
			var line = L.polyline([[parseFloat(link['repeaterlat']), parseFloat(link['repeaterlon'])],
								   [parseFloat(link['locationlat']), parseFloat(link['locationlon'])]],
								  { color: "#ff0000" });

			
			stations[link['listeningStation']]['lines'].push(line);
			stations[link['listeningStation']]['mark']['ws6z_lines'].push(line);

			repeaters[link['repeaterid']]['lines'].push(line);
			repeaters[link['repeaterid']]['mark']['ws6z_lines'].push(line);
		}
	}

	// add the links between the stations (simplexes)
	for (simplexid in simplexes) {
		if (simplexes.hasOwnProperty(simplexid)) {
			var simplex = simplexes[simplexid];
			var line = L.polyline([[parseFloat(simplex['heardlat']), parseFloat(simplex['heardlon'])],
								   [parseFloat(simplex['fromlat']), parseFloat(simplex['fromlon'])]],
								  { color: "#ff8000" });

			
			stations[simplex['heardstation']]['lines'].push(line);
			stations[simplex['heardstation']]['mark']['ws6z_lines'].push(line)

			stations[simplex['fromstation']]['lines'].push(line);
			stations[simplex['fromstation']]['mark']['ws6z_lines'].push(line)
		}
	}


	L.control.layers(null,  { 'Repeaters': repeaterGroup,
							  'Stations':  stationGroup} ).addTo(map);


	function toggleLines(lines, shown) {
		var showpopup = true;

		for (line in lines) {
			if (lines.hasOwnProperty(line)) {
				//lines[line].hide();
				if (shown) {
					map.removeLayer(lines[line]);
					// something was shown, so don't show the popup
					showpopup = false;
				} else {
					map.addLayer(lines[line]);
				}
			}
		}

		return [shown, showpopup];
	}

	function showPopup(forobj) {
		var popup = L.popup({ offset: forobj.offset })
	  		.setLatLng([parseFloat(forobj.lat), parseFloat(forobj.lon)])
			.setContent(forobj.title)
			.openOn(map);
	}

	function onMarkerClick(e) {
		// 'this' should be a marker
		var lines = this.ws6z_lines;
		var shown = this.ws6z_shown;
		var showpopup = false;

		if (lines.length === 0) {
			showpopup = true;
		}

		var results = toggleLines(lines, shown);
		shown = results[0];
		if (!showpopup) {
			showpopup = results[1];
		}

		if (showpopup) {
			showPopup(this.ws6z_obj);
			// var popup = L.popup({ offset: this.ws6z_obj.offset })
	  		// 	.setLatLng(this._latlng)
			// 	.setContent(this.ws6z_obj.title)
			// 	.openOn(map);
		}

		this.ws6z_shown = !shown;
	}

	self['findCallsign'] = function(callsign) {
		//callsign = callsign.toUpperCase();
		var matcher = new RegExp(callsign, "i");

		for (station in allStations) {
			if (allStations.hasOwnProperty(station)) {
				if (stations[station].callsign.match(matcher) ||
					(stations[station].firstname && stations[station].firstname.match(matcher)) ||
					(stations[station].lastname && stations[station].lastname.match(matcher)) ||
					(stations[station].locationname && stations[station].locationname.match(matcher)) ||
					(stations[station].title && stations[station].title.match(matcher))
				   ) {
					showPopup(stations[station]);
					return;
				}
			}
		}
		for (repeater in allRepeaters) {
			if (allRepeaters.hasOwnProperty(repeater)) {
				if (repeaters[repeater].callsign.match(matcher) ||
					(repeaters[repeater].repeatername && repeaters[repeater].repeatername.match(matcher)) ||
					(repeaters[repeater].repeaternotes && repeaters[repeater].repeaternotes.match(matcher)) ||
					(repeaters[repeater].title && repeaters[repeater].title.match(matcher))) {
					showPopup(repeaters[repeater]);
					return;
				}
			}
		}
	}

	self['toggleAllStations'] = function() {
		for (station in allStations) {
			if (allStations.hasOwnProperty(station)) {
				toggleLines(allStations[station]['lines'], false);
			}
		}
	}

	self['toggleAllRepeaters'] = function() {
		for (repeater in allRepeaters) {
			if (allRepeaters.hasOwnProperty(repeater)) {
				toggleLines(allRepeaters[repeater]['lines'], false);
			}
		}
	}

	self['hideAllStations'] = function() {
		for (station in allStations) {
			if (allStations.hasOwnProperty(station)) {
				toggleLines(allStations[station]['lines'], true);
			}
		}
	}

	return self;
}
