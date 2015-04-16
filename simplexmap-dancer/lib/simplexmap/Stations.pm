package simplexmap::Stations;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::DataFormValidator;
use Data::FormValidator::Constraints qw(:closures);
use Data::Dumper;

get '/stations' => sub {
	my $listh;
	if (param('mine')) {
		$listh = database()->prepare_cached("select * from locations where locationperson = ?");
	} else {
		$listh = database()->prepare_cached("select * from locations
                                         inner join people on locationperson = people.id 
                                                where locationprivacy = 'P' or locationperson = ?");
	}

	$listh->execute(session('user'));
	my $list = $listh->fetchall_arrayref({});
	
	template 'stations/list.tt' => { list => $list, mine => (param('mine') ? 1 : 0) }; 
};

get '/stations/new' => sub {

	my $symbolsh = database()->prepare_cached("select * from symbols");
	$symbolsh->execute();
	my $symbols = $symbolsh->fetchall_arrayref({});
	$symbolsh->finish;
	
	template 'stations/new' => { symbols => $symbols };
};

post '/stations' => sub {
	debug("-------------- here top");

	my $results = 
	  dfv({ required => ['latitude', 'longitude', 'name', 'visibility', 'stationtype'],
	        optional => ['antenna', 'transmitter'],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         latitude       => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         longitude      => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         stationtype    => qr/^[0-9]+$/,
	         visibility     => qr/^(private|friends|friendsandgroups|public)$/,
	        }
	      });

	if ($results->has_invalid || $results->has_missing) {
		debug("fail submit");
		debug($results->msgs);
		return template 'stations/new' => { messages => $results->msgs };
	}

	my $vals = $results->valid;

	my %privmap = (
	               public  => 'P',
	               private => 'M',
	               friendsandgroups => 'G',
	               friends => 'F'
	              );
	$vals->{'visibility'} = $privmap{$vals->{'visibility'}};

	my $symbolsh = database()->prepare_cached("select * from symbols where symbolid = ?");
	$symbolsh->execute($vals->{'stationtype'});
	my $row = $symbolsh->fetchrow_arrayref();
	$symbolsh->finish();

	if (!$row) {
		# no symbol found
		return template 'error' => { error => "Illegal station type" };
	}

	my $insh = database()->prepare_cached("
       insert into locations (locationperson, locationname, locationlat, locationlon,
                              locationtransmiter, locationantenna, locationprivacy, locationsymbol)
                      values (?, ?, ?, ?, ?, ?, ?, ?)");
	$insh->execute(session('user'), $vals->{'name'}, $vals->{'latitude'}, $vals->{'longitude'},
	               $vals->{'transmitter'}, $vals->{'antenna'}, $vals->{'visibility'}, $vals->{'stationtype'} || 1);

	redirect '/stations';
};

######################################################################
# repeater details
get '/stations/:num' => sub {
	my $num = param('num');
	if ($num !~ /^[0-9]+$/) {
		return template 'error' => { error => "Unknown Station Id" }
	}

	my $listh = database()->prepare_cached("select * from locations
                                         left join people
                                                on people.id = locations.locationperson
                                             where locationid = ?
                                               and (locationprivacy = 'P'
                                                    or locationperson = ?)");
	$listh->execute($num, session('user'));
	my $station = $listh->fetchrow_hashref();
	$listh->finish;

	my $repeatersh = database()->prepare_cached("select *, people.callsign as personcallsign from repeatersignals
                                          inner join repeaters
                                                  on repeaters.repeaterid = repeatersignals.repeaterid
                                          inner join locations
                                                  on listeningStation = locationid
                                          inner join people
                                                  on people.id = locations.locationperson
                                               where listeningStation = ?
                                                 and repeaterStrength > -1
                                                 and (repeaterpublic = 'Y'
                                                      or repeaterowner = ?)");
	$repeatersh->execute($num, session('user'));
	my $repeaters = $repeatersh->fetchall_arrayref({});
	$repeatersh->finish;

	my $simplexesh = database()->prepare_cached("
                                            select 
                                                   locheard.locationlat    as heardlat,
                                                   locheard.locationlon    as heardlon,
                                                   locheard.locationperson as heardperson,
                                                   locheard.locationname   as heardname,
                                                   personheard.firstname   as firstname,
                                                   personheard.lastname    as lastname,
                                                   personheard.callsign    as heardcallsign,
                                                   personfrom.callsign     as fromcallsign,
                                                   from_unixtime(timelogged) as timelogged,
                                                   rating
                                  from connections
                                         left join locations as locheard
                                                on heard = locheard.locationid
                                         left join locations as locfrom
                                                on listener = locfrom.locationid
                                         left join people as personfrom
                                                on locfrom.locationperson = personfrom.id
                                         left join people as personheard
                                                on locheard.locationperson = personheard.id
                                             where personfrom.id = ?
                                                or personheard.id = ?
    ");
	
	$simplexesh->execute(session('user'), session('user'));
	my $people = $simplexesh->fetchall_arrayref({});
	$simplexesh->finish();

	print STDERR "hi ---------------------------------------------------------------------- \n";
	print STDERR Dumper($people);
	
	template 'stations/details' => { location => $station,
	                                 repeaters => $repeaters,
	                                 people => $people };
};


1;
