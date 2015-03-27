package simplexmap::Simplex;

use Data::Dumper;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::DataFormValidator;
use Data::FormValidator::Constraints qw(:closures);

######################################################################
# New simplexes

sub simplex_list {
	my ($messages, $vals) = @_;
	
	my $listh = database()->prepare_cached("select * from connections
                                         left join locations  
                                                on heard = locations.locationid
                                         left join people  
                                                on locationperson = people.id
                                             where listener = ?"); # XXX: limit by distance from station location
	
	$listh->execute(session('user'));
	my $simplexes = $listh->fetchall_arrayref({});

	template 'simplex/list' => { simplexes => $simplexes, vals => $vals, messages => $messages };
};

get '/simplex' => \&simplex_list;

get '/simplex/new' => sub {
	template 'simplex/new';
};

post '/simplex' => sub {
	debug("-------------- simplex top");

	my $results = 
	  dfv({ required => ['signal', 'callsign'],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         callsign       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         signal         => qr/^-?[0-9]+$/,
	        }
	      });

	my $vals = $results->valid;

	if ($results->has_invalid || $results->has_missing) {
		debug("fail");
		debug($results->msgs);
		return simplex_list($results->msgs, $vals);
	}

	# XXX: need to allow them to selcet a specific location
	my $insh = database()->prepare_cached("
       insert into connections (eventid, listener, heard, comment, rating)
                      select ?, ?, locations.locationid, ?, ?
                       from people
                 inner join locations on people.id = locations.locationperson
                      where people.callsign = ?
                      limit 1");

	# insert the new signal
	my $res = $insh->execute(0,
	                         session('user'),
	                         '',
	                         $vals->{'signal'},
	                         $vals->{'callsign'}
	                        );

	if ($res == 0) {
		return simplex_list({ callsign => "callsign not found or not registered" }, $vals);
	}

	redirect '/simplex';
};

######################################################################
# signals
#

get '/simplex/signalstart' => sub {
	my $listh = database()->prepare_cached("select * from locations where locationperson = ?");

	$listh->execute(session('user'));
	my $list = $listh->fetchall_arrayref({});

	redirect '/simplex/new' if ($#$list == -1);

	template 'simplex/signalstart' => { stations => $list };
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


get '/simplex/signals' => sub {
	# XXX: limit by distance from station location

	my $station = get_station_num();
	redirect '/simplex/signalstart' if (!$station);

	my $sth = database()->prepare_cached("select * from locations
                                           where locationperson = ?
                                             and locationid = ?");
	$sth->execute(session('user'), $station->{'locationid'});
	my $row = $sth->fetchrow_hashref();
	$sth->finish;

	if (!$row) {
		redirect '/simplex/signalstart';
	}

	my $stationName = $row->{'locationname'};

	my $listh = database()->prepare_cached(
    	 "select simplexes.simplexid as simplexid, simplexnotes, simplexcallsign, simplexlat, simplexlon,
                 simplexestrength, sendingStrength
            from simplexes
       left join simplexesignals
              on simplexes.simplexid = simplexesignals.simplexid
                 and listeningStation = ?
           where simplexpublic = 'Y' or simplexowner = ?");

	$listh->execute($station->{'locationid'}, session('user'));
	my $list = $listh->fetchall_arrayref({});

	template 'simplex/signals' => { list => $list,
	                                  station => $station
	                                }; 
};

post '/simplex/signals' => sub {
	debug("starting signals: " . param('station'));

	my $station = get_station_num();
	redirect '/simplex/signalstart' if (!$station);
	
	my $listh = database()->prepare_cached("select * from simplexes
                                             where simplexpublic = 'Y'
                                                or simplexowner = ?"); # XXX: limit by distance from station location
	$listh->execute(session('user'));
	my $list = $listh->fetchall_arrayref({});
	
	my $uph = database()->prepare_cached("update simplexesignals
                                             set simplexestrength = ?, sendingStrength = ?
                                           where simplexid = ? and listeningStation = ?");
	my $insh = database()->prepare_cached("insert into simplexesignals (simplexid, listeningStation, simplexestrength, sendingStrength) values(?, ?, ?, ?)");

	my $level;
	
	foreach my $simplex (@$list) {
		debug("checking simplex: $simplex->{'simplexid'}");
		$level = param("simplexestrength_$simplex->{'simplexid'}");
		if (defined($level)) {
			# extract the level
			$level = int($level);
			next if ($level < -2 || $level > 9);
			
			next if ($level !~ /^-?\d$/);
			
			my $count = $uph->execute($level, 0, $simplex->{'simplexid'}, $station->{'locationid'});
			if ($count == 0) {
				# no row exists; insert it
				$insh->execute($simplex->{'simplexid'}, $station->{'locationid'}, $level, 0);
			}
		}
	}
	
	redirect '/simplex';
};

######################################################################
# Simplex Map
get '/simplex/map' => sub {
	# get all the simplexes
	my $simplexesh = database()->prepare_cached("select * from simplexes
                                                  where simplexpublic = 'Y' or simplexowner = ?");
	$simplexesh->execute(session('user'));
	my $allsimplexes = $simplexesh->fetchall_hashref('simplexid');
	$allsimplexes = to_json($allsimplexes);

	# get all the stations
	my $stationsh = database()->prepare_cached("select * from locations
                                            inner join people
                                                    on locations.locationperson = people.id");
	$stationsh->execute();
	my $allstations = $stationsh->fetchall_hashref('locationid');
	$allstations = to_json($allstations);

	# fetch all the links
	my $listh = database()->prepare_cached(
    	 "select simplexes.simplexid, listeningStation, simplexestrength, sendingStrength,
                 locationlat, locationlon, simplexlat, simplexlon
            from simplexesignals
      inner join locations on locationId = listeningStation
      inner join simplexes on simplexes.simplexid = simplexesignals.simplexid
           where simplexestrength is not null and simplexestrength > -1
             and simplexpublic = 'Y' or simplexowner = ?");
	warn(database()->errstr) if (!$listh);

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

	$links = to_json($links);

	template 'simplex/map' => { simplexes => $allsimplexes,
	                              stations => $allstations,
	                              links => $links,
	                              centeron => $station};
};

######################################################################
# simplex details
get '/simplex/:num' => sub {
	my $num = param('num');
	if ($num !~ /^[0-9]+$/) {
		return template 'error' => { error => "illegal URL" }
	}

	my $listh = database()->prepare_cached("select * from simplexes
                                             where simplexid = ?
                                               and (simplexpublic = 'Y'
                                                    or simplexowner = ?)");
	$listh->execute($num, session('user'));
	my $simplex = $listh->fetchrow_hashref();
	$listh->finish;

	if (!$simplex) {
		return template 'error' => { error => "Unknown simplex" }
	}
   
	template 'simplex/details' => { simplex => $simplex };
};


1;
