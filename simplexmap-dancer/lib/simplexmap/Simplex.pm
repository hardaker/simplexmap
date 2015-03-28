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
	
	my $listh = database()->prepare_cached("select 
                                                   locheard.locationlat    as heardlat,
                                                   locheard.locationlon    as heardlon,
                                                   locheard.locationperson as heardperson,
                                                   locheard.locationname   as heardname,
                                                   personheard.callsign    as heardcallsign,
                                                   locfrom.locationlat 	   as fromlat,
                                                   locfrom.locationlon 	   as fromlon,
                                                   locfrom.locationperson  as fromperson,
                                                   locfrom.locationname    as fromname,
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
                                             where personfrom.id = ?"); # XXX: limit by distance from station location

                                               
	$listh->execute(session('user'));
	my $simplexes = $listh->fetchall_arrayref({});

	my $listh = database()->prepare_cached("select * from locations where locationperson = ?");
	$listh->execute(session('user'));
	my $locations = $listh->fetchall_arrayref({});

	template 'simplex/list' => { simplexes => $simplexes,
	                             vals => $vals,
	                             locations => $locations,
	                             messages => $messages };
};

get '/simplex' => \&simplex_list;

post '/simplex' => sub {
	debug("-------------- simplex top");

	my $results = 
	  dfv({ required => ['signal', 'callsign', 'location'],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         callsign       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         signal         => qr/^[0-9]+$/,
	         location       => qr/^[0-9]+$/,
	        }
	      });

	my $vals = $results->valid;

	debug($vals);
	
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
	                         $vals->{'location'},
	                         '',
	                         $vals->{'signal'},
	                         $vals->{'callsign'}
	                        );

	if ($res == 0) {
		return simplex_list({ callsign => "callsign not found or not registered" }, $vals);
	}

	redirect '/simplex';
};

1;
