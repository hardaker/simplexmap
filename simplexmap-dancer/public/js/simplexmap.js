function createmap(lat, lon, repeaters, stations, links) {
	var currentLine;

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

			repeaterLayerObjs[repeaterLayerObjs.length] = repeatMark;

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
				stations[station]['locationname'] + "</a></strong><br />";

			stations[station]['offset'] = [0, -iconHomeSize/2];

			var stationMark = 
				L.marker([parseFloat(stations[station]['locationlat']),
						  parseFloat(stations[station]['locationlon'])],
						 {title: stations[station]['title'],
						  icon: homeIcon}).addTo(map)
			stationLayerObjs[stationLayerObjs.length] = stationMark;

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

	// add the links between the various objects
	for (linkid in links) {
		if (links.hasOwnProperty(linkid)) {
			var link = links[linkid];
			var line = L.polyline([[parseFloat(link['repeaterlat']), parseFloat(link['repeaterlon'])],
								   [parseFloat(link['locationlat']), parseFloat(link['locationlon'])]]);

			
			stations[link['listeningStation']]['lines'][stations[link['listeningStation']]['lines'].length] = line;
			stations[link['listeningStation']]['mark']['ws6z_lines'][stations[link['listeningStation']]['mark']['ws6z_lines'].length] = line;

			repeaters[link['repeaterid']]['lines'][repeaters[link['repeaterid']]['lines'].length] = line;

			repeaters[link['repeaterid']]['mark']['ws6z_lines'][repeaters[link['repeaterid']]['mark']['ws6z_lines'].length] = line;
		}
	}

	L.control.layers(null,  { 'Repeaters': repeaterGroup,
							  'Stations':  stationGroup} ).addTo(map);


	function onMarkerClick(e) {
		// 'this' should be a marker
		var lines = this.ws6z_lines;
		var shown = this.ws6z_shown;
		var showpopup = false;

		if (lines.length == 0) {
			showpopup = true;
		}
		
		for (line in lines) {
			if (lines.hasOwnProperty(line)) {
				//lines[line].hide();
				if (shown) {
					map.removeLayer(lines[line]);
				} else {
					map.addLayer(lines[line]);
					// pop up the display
					showpopup = true;
				}
			}
		}

		if (showpopup) {
			var popup = L.popup({ offset: this.ws6z_obj.offset })
	  			.setLatLng(this._latlng)
				.setContent(this.ws6z_obj.title)
				.openOn(map);
		}
		
		this.ws6z_shown = !shown;
	}

}
