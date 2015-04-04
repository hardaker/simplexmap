package simplexmap::Stations;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::DataFormValidator;
use Data::FormValidator::Constraints qw(:closures);

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
	template 'stations/new';
};

post '/stations' => sub {
	debug("-------------- here top");

	my $results = 
	  dfv({ required => ['latitude', 'longitude', 'name', 'visibility'],
	        optional => ['antenna', 'transmitter'],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         latitude       => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         longitude      => qr/^[-+]?[0-9]+\.[0-9]+$/,
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

	my $insh = database()->prepare_cached("
       insert into locations (locationperson, locationname, locationlat, locationlon,
                              locationtransmiter, locationantenna, locationprivacy)
                      values (?, ?, ?, ?, ?, ?, ?)");
	$insh->execute(session('user'), $vals->{'name'}, $vals->{'latitude'}, $vals->{'longitude'},
	               $vals->{'transmitter'}, $vals->{'antenna'}, $vals->{'visibility'});

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

	template 'stations/details' => { location => $station, repeaters => $repeaters };
};


1;
