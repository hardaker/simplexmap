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
                                             where personfrom.id = ?
                                                or personheard.id = ?"); # XXX: limit by distance from station location

                                               
	$listh->execute(session('user'), session('user'));
	my $simplexes = $listh->fetchall_arrayref({});

	$listh = database()->prepare_cached("select * from locations where locationperson = ?");
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
	  dfv({ required => ['signal1', 'callsign1', 'location'],
	        filters => 'trim',
	        optional => [qw(signal2 callsign2 signal3 callsign3 signal4 callsign4 signal5 callsign5)],
	        constraint_methods => 
	        {
	         callsign1       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         callsign2       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         callsign3       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         callsign4       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         callsign5       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         signal1         => qr/^-?[0-9]+$/,
	         signal2         => qr/^-?[0-9]+$/,
	         signal3         => qr/^-?[0-9]+$/,
	         signal4         => qr/^-?[0-9]+$/,
	         signal5         => qr/^-?[0-9]+$/,
	         location        => qr/^?[0-9]+$/,
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
       insert into connections (eventid, listener, heard, comment, rating, timelogged)
                      select ?, ?, locations.locationid, ?, ?, ?
                       from people
                 inner join locations on people.id = locations.locationperson
                      where people.callsign = ?
                      limit 1");

	# insert the new signal
	database()->begin_work();
	foreach my $num (qw(1 2 3 4 5)) {
		if (defined($vals->{"signal$num"}) && defined($vals->{"callsign$num"}) &&
		    $vals->{"signal$num"} > -1) {
			my $res = $insh->execute(0,
			                         $vals->{'location'},
			                         '',
			                         $vals->{"signal$num"},
			                         time(),
			                         $vals->{"callsign$num"},
			                        );
			if ($res == 0) {
				database()->rollback();
				return simplex_list({ "callsign$num" => "<font color=\"red\">* callsign not found or not registered</font>",
				                      "callsign" => "<font color=\"red\">* callsign not found or not registered</font>"}, $vals);
			}
		}
	}

	database()->commit();
	$insh->finish();
	redirect '/simplex';
};

1;
