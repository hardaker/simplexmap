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
	
	template 'stations/list.tt' => { list => $list }; 
};

get '/stations/new' => sub {
	template 'stations/new';
};

post '/stations' => sub {
	debug("-------------- here top");

	my $results = 
	  dfv({ required => ['latitude', 'longitude', 'identifier'],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         latitude       => qr/^[-+]?[0-9]+\.[0-9]+$/,
	         longitude      => qr/^[-+]?[0-9]+\.[0-9]+$/,
	        }
	      });

	if ($results->has_invalid || $results->has_missing) {
		debug("fail");
		debug($results->msgs);
		return template 'stations/new' => { messages => $results->msgs };
	}

	my $vals = $results->valid;

	debug("-------------- here");

	my $insh = database()->prepare_cached("
       insert into locations (locationperson, locationname, locationlat, locationlon)
                      values (?, ?, ?, ?)");
	$insh->execute(session('user'), $vals->{'identifier'}, $vals->{'latitude'}, $vals->{'longitude'});

	redirect '/stations';
};

1;
