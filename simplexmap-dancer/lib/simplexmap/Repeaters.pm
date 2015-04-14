package simplexmap::Repeaters;

use Data::Dumper;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::DataFormValidator;
use Data::FormValidator::Constraints qw(:closures);

######################################################################
# New repeaters

get '/repeaters' => sub {
	my $listh = database()->prepare_cached("select * from repeaters
                                         left join people  
                                                on repeaterowner = people.id
                                             where repeaterpublic = 'Y'
                                                or repeaterowner = ?"); # XXX: limit by distance from station location
	$listh->execute(session('user'));
	my $repeaters = $listh->fetchall_arrayref({});

	template 'repeaters/list' => { repeaters => $repeaters };
};

get '/repeaters/new' => sub {
	template 'repeaters/new';
};

post '/repeaters' => sub {
	debug("-------------- here top");

	my $results = 
	  dfv({ required => ['name', 'callsign', 'latitude', 'longitude', 'visibility'],
	        optional => [qw(frequency offset pltone dcstone notes)],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         latitude       => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         longitude      => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         callsign       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         visibility     => qr/^(private|public)$/,
	         frequency      => qr/^[0-9]+\.[0-9]+\s*[a-zA-Z]*$/,
	         offset         => qr/^(\+|-)$/,
	         pltone         => qr/^[0-9]+\.?[0-9]+$/,
	         dcstone        => qr/^[0-9]+$/,
	        }
	      });

	if ($results->has_invalid || $results->has_missing) {
		debug("fail");
		debug($results->msgs);
		return template 'repeaters/new' => { messages => $results->msgs };
	}

	my $vals = $results->valid;

	$vals->{'callsign'} = uc($vals->{'callsign'});

	my $insh = database()->prepare_cached("
       insert into repeaters (repeaterowner, repeatername, repeatercallsign, repeaterlat, repeaterlon,
                              repeaternotes, repeaterpublic, repeaterfreq, repeateroffset,
                              repeaterpl, repeaterdcs)
                      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
	$insh->execute(session('user'), $vals->{'name'}, $vals->{'callsign'}, $vals->{'latitude'}, $vals->{'longitude'},
	               $vals->{'notes'},
	               ($vals->{'visibility'} eq 'public' ? 'Y' : 'N'), $vals->{'frequency'}, $vals->{'offset'},
	               $vals->{'pltone'}, $vals->{'dcstone'});

	redirect '/repeaters';
};

######################################################################
# signals
#

get '/repeaters/signalstart' => sub {
	my $listh = database()->prepare_cached("select * from locations where locationperson = ?");

	$listh->execute(session('user'));
	my $list = $listh->fetchall_arrayref({});

	redirect '/repeaters/new' if ($#$list == -1);

	template 'repeaters/signalstart' => { stations => $list };
};

sub get_station_num {
	my $station = param('station');
	if (!$station) {
		return undef;
	}

	my $sth = database()->prepare_cached("select * from locations
                                           where locationperson = ?
                                             and locationid = ?");
	$sth->execute(session('user'), $station);
	my $row = $sth->fetchrow_hashref();
	$sth->finish;

	if (!$row) {
		return undef;
	}

	return $row;
}


get '/repeaters/signals' => sub {
	# XXX: limit by distance from station location

	my $station = get_station_num();
	redirect '/repeaters/signalstart' if (!$station);

	my $sth = database()->prepare_cached("select * from locations
                                           where locationperson = ?
                                             and locationid = ?");
	$sth->execute(session('user'), $station->{'locationid'});
	my $row = $sth->fetchrow_hashref();
	$sth->finish;

	if (!$row) {
		redirect '/repeaters/signalstart';
	}

	my $stationName = $row->{'locationname'};

	my $listh = database()->prepare_cached(
    	 "select repeaters.repeaterid as repeaterid, repeaternotes, repeatercallsign, repeaterlat, repeaterlon,
                 repeaterStrength, sendingStrength, repeatername
            from repeaters
       left join repeatersignals
              on repeaters.repeaterid = repeatersignals.repeaterid
                 and listeningStation = ?
           where repeaterpublic = 'Y' or repeaterowner = ?");

	$listh->execute($station->{'locationid'}, session('user'));
	my $list = $listh->fetchall_arrayref({});

	template 'repeaters/signals' => { list => $list,
	                                  station => $station
	                                }; 
};

post '/repeaters/signals' => sub {
	debug("starting signals: " . param('station'));

	my $station = get_station_num();
	redirect '/repeaters/signalstart' if (!$station);
	
	my $listh = database()->prepare_cached("select * from repeaters
                                             where repeaterpublic = 'Y'
                                                or repeaterowner = ?"); # XXX: limit by distance from station location
	$listh->execute(session('user'));
	my $list = $listh->fetchall_arrayref({});
	
	my $uph = database()->prepare_cached("update repeatersignals
                                             set repeaterStrength = ?, sendingStrength = ?
                                           where repeaterid = ? and listeningStation = ?");
	my $insh = database()->prepare_cached("insert into repeatersignals (repeaterid, listeningStation, repeaterStrength, sendingStrength) values(?, ?, ?, ?)");

	my $level;
	
	foreach my $repeater (@$list) {
		debug("checking repeater: $repeater->{'repeaterid'}");
		$level = param("repeaterStrength_$repeater->{'repeaterid'}");
		if (defined($level)) {
			# extract the level
			$level = int($level);
			next if ($level < -2 || $level > 9);
			
			next if ($level !~ /^-?\d$/);
			
			my $count = $uph->execute($level, 0, $repeater->{'repeaterid'}, $station->{'locationid'});
			if ($count == 0) {
				# no row exists; insert it
				$insh->execute($repeater->{'repeaterid'}, $station->{'locationid'}, $level, 0);
			}
		}
	}
	
	redirect '/repeaters';
};

######################################################################
# Repeater Map
get '/repeaters/map' => sub {
	# get all the repeaters
	my $repeatersh = database()->prepare_cached("select *, repeaterlat as lat, repeaterlon as lon,
                                                   repeatercallsign as callsign
                                                   from repeaters
                                                  where repeaterpublic = 'Y' or repeaterowner = ?");
	$repeatersh->execute(session('user'));
	my $allrepeaters = $repeatersh->fetchall_hashref('repeaterid');
	$allrepeaters = to_json($allrepeaters);

	# get all the stations
	my $stationsh = database()->prepare_cached("select *, locationlat as lat, locationlon as lon
                                                  from locations
                                            inner join people
                                                    on locations.locationperson = people.id
                                            inner join symbols
                                                    on locationsymbol = symbolid");
	$stationsh->execute();
	my $allstations = $stationsh->fetchall_hashref('locationid');
	$allstations = to_json($allstations);

	# fetch all the repeater links
	my $listh = database()->prepare_cached(
    	 "select repeaters.repeaterid, listeningStation, repeaterStrength, sendingStrength,
                 locationlat, locationlon, repeaterlat, repeaterlon
            from repeatersignals
      inner join locations on locationId = listeningStation
      inner join repeaters on repeaters.repeaterid = repeatersignals.repeaterid
           where repeaterStrength is not null and repeaterStrength > -1
             and (repeaterpublic = 'Y' or repeaterowner = ?)");
	warn(database()->errstr) if (!$listh);

	# fetch symbol details
	my $symbolsh = database()->prepare_cached("select * from symbols");
	$symbolsh->execute();
	my $symbols = $symbolsh->fetchall_arrayref({});
	$symbolsh->finish;

	# fetch repeater link details
	my $repeaterlinksh = database()->prepare_cached("select leftrep.repeaterid   as leftid,
                                                            leftrep.repeaterlat  as leftlat,
                                                            leftrep.repeaterlon  as leftlon,
                                                            rightrep.repeaterid  as rightid,
                                                            rightrep.repeaterlat as rightlat,
                                                            rightrep.repeaterlon as rightlon
                                                       from repeaterlinks
                                                 inner join repeaters as leftrep
                                                         on leftrep.repeaterid = repeaterlinks.fromid
                                                 inner join repeaters as rightrep
                                                         on rightrep.repeaterid = repeaterlinks.toid");
	$repeaterlinksh->execute();
	my $repeaterlinks = $repeaterlinksh->fetchall_arrayref({});
	$repeaterlinksh->finish;
	
	# fetch all the simplex links
	my $simph = database()->prepare_cached("select 
                                                   locheard.locationlat    as heardlat,
                                                   locheard.locationlon    as heardlon,
                                                   locheard.locationid     as heardstation,
                                                   locheard.locationperson as heardperson,
                                                   locfrom.locationlat 	   as fromlat,
                                                   locfrom.locationlon 	   as fromlon,
                                                   locfrom.locationid      as fromstation,
                                                   locfrom.locationperson  as fromperson
                                              from connections
                                         left join locations as locheard
                                                on heard = locheard.locationid
                                         left join people as peopleheard
                                                on locheard.locationperson = peopleheard.id
                                         left join locations as locfrom
                                                on listener = locfrom.locationid
                                         left join people as peoplefrom
                                                on locfrom.locationperson = peoplefrom.id"); # XXX: limit by distance from station location
	warn(database()->errstr) if (!$simph);
	
	# find the first station that the user owns, if any, to center the map on
	my $stationh = database()->prepare_cached("select * from locations where locationperson = ? limit 1");
	$stationh->execute(session('user'));
	my $station = $stationh->fetchrow_hashref();
	$stationh->finish;

	if (!$station) {
		# they haven't logged one; fake one in davis
		$station = {
		            locationlat => 38.55,
		            locationlon => -121.7,
		           };
	}

	$listh->execute(session('user'));
	my $links = $listh->fetchall_arrayref({});

	$simph->execute();
	my $simplexes = $simph->fetchall_arrayref({});

	$links = to_json($links);
	$simplexes = to_json($simplexes);
	$symbols = to_json($symbols);
	$repeaterlinks = to_json($repeaterlinks);

	template 'repeaters/map' => { repeaters 	=> $allrepeaters,
	                              stations 		=> $allstations,
	                              symbols  		=> $symbols,
	                              repeaterlinks	=> $repeaterlinks,
	                              links    		=> $links,
	                              simplex  		=> $simplexes,
	                              centeron 		=> $station};
};

######################################################################
# repeater details
get '/repeaters/:num' => sub {
	my $num = param('num');
	if ($num !~ /^[0-9]+$/) {
		return template 'error' => { error => "Unknown Repeater ID" }
	}

	my $listh = database()->prepare_cached("select * from repeaters
                                             where repeaterid = ?
                                               and (repeaterpublic = 'Y'
                                                    or repeaterowner = ?)");
	$listh->execute($num, session('user'));
	my $repeater = $listh->fetchrow_hashref();
	$listh->finish;

	if (!$repeater) {
		return template 'error' => { error => "Unknown repeater" }
	}

	my $peopleh = database()->prepare_cached("select *, people.callsign as personcallsign from repeatersignals
                                          inner join repeaters
                                                  on repeaters.repeaterid = repeatersignals.repeaterid
                                          inner join locations
                                                  on listeningStation = locationid
                                          inner join people
                                                  on people.id = locations.locationperson
                                               where repeaters.repeaterid = ?
                                                 and repeaterStrength > -1
                                                 and (repeaterpublic = 'Y'
                                                      or repeaterowner = ?)");
	$peopleh->execute($num, session('user'));
	my $people = $peopleh->fetchall_arrayref({});
	$peopleh->finish;
   
	template 'repeaters/details' => { repeater => $repeater, people => $people };
};


1;
