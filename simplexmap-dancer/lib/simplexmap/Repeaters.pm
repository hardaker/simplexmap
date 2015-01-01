package simplexmap::Repeaters;

use Data::Dumper;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::DataFormValidator;
use Data::FormValidator::Constraints qw(:closures);

get '/repeaters' => sub {
	my $listh = database()->prepare_cached("select * from repeaters where repeaterowner = ?");
	$listh->execute(session('user'));
	my $list = $listh->fetchall_arrayref({});
	
	template 'repeaters' => { list => $list }; 
};

######################################################################
# New repeaters

get '/repeaters/list' => sub {
	my $listh = database()->prepare_cached("select * from repeaters"); # XXX: limit by distance from station location
	$listh->execute();
	my $repeaters = $listh->fetchall_arrayref({});

	template 'repeaters/list' => { repeaters => $repeaters };
};

get '/repeaters/new' => sub {
	template 'repeaters/new';
};

post '/repeaters' => sub {
	debug("-------------- here top");

	my $results = 
	  dfv({ required => ['latitude', 'longitude', 'identifier', 'callsign'],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         latitude       => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         longitude      => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         callsign       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	        }
	      });

	if ($results->has_invalid || $results->has_missing) {
		debug("fail");
		debug($results->msgs);
		return template 'repeaters/new' => { messages => $results->msgs };
	}

	my $vals = $results->valid;

	my $insh = database()->prepare_cached("
       insert into repeaters (repeaternotes, repeaterowner, repeatercallsign, repeaterlat, repeaterlon)
                      values (?, ?, ?, ?, ?)");
	$insh->execute($vals->{'identifier'}, session('user'), $vals->{'callsign'}, $vals->{'latitude'}, $vals->{'longitude'});

	redirect '/repeaters';
};

######################################################################
# signals
#

get '/repeaters/signalstart' => sub {
	my $listh = database()->prepare_cached("select * from locations where locationperson = ?");

	$listh->execute(session('user'));
	my $list = $listh->fetchall_arrayref({});

	redirect '/stations/new' if ($#$list == -1);

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
                 repeaterStrength, sendingStrength
            from repeaters
       left join repeatersignals
              on repeaters.repeaterid = repeatersignals.repeaterid
                 and listeningStation = ?");

	$listh->execute($station->{'locationid'});
	my $list = $listh->fetchall_arrayref({});

	template 'repeaters/signals' => { list => $list,
	                                  station => $station
	                                }; 
};

post '/repeaters/signals' => sub {
	debug("starting signals: " . param('station'));

	my $station = get_station_num();
	redirect '/repeaters/signalstart' if (!$station);
	
	my $listh = database()->prepare_cached("select * from repeaters"); # XXX: limit by distance from station location
	$listh->execute();
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
	
	redirect '/repeaters/list';
};

######################################################################
# Repeater Map
get '/repeaters/map' => sub {
	my $repeatersh = database()->prepare_cached("select * from repeaters");
	$repeatersh->execute();
	my $allrepeaters = $repeatersh->fetchall_hashref('repeaterid');
	$allrepeaters = to_json($allrepeaters);

	my $stationsh = database()->prepare_cached("select * from locations
                                            inner join people
                                                    on locations.locationperson = people.id");
	$stationsh->execute();
	my $allstations = $stationsh->fetchall_hashref('locationid');
	$allstations = to_json($allstations);
	
	my $listh = database()->prepare_cached(
    	 "select repeaters.repeaterid, listeningStation, repeaterStrength, sendingStrength,
                 locationlat, locationlon, repeaterlat, repeaterlon
            from repeatersignals
      inner join locations on locationId = listeningStation
      inner join repeaters on repeaters.repeaterid = repeatersignals.repeaterid
           where repeaterStrength is not null and repeaterStrength > -1");
	warn(database()->errstr) if (!$listh);

	$listh->execute();
	my $links = $listh->fetchall_arrayref({});

	$links = to_json($links);

	template 'repeaters/map' => { repeaters => $allrepeaters,
	                              stations => $allstations,
	                              links => $links };
};

1;
