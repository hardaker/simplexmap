package simplexmap::Repeaters;

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
get '/repeaters/signals' => sub {
	my $listh = database()->prepare_cached("select * from repeaters"); # XXX: limit by distance from station location
	$listh->execute();
	my $list = $listh->fetchall_arrayref({});
	
	template 'repeaters/signals' => { list => $list }; 
};

post '/repeaters/signals' => sub {
	debug("starting signals");
	
	my $listh = database()->prepare_cached("select * from repeaters"); # XXX: limit by distance from station location
	$listh->execute();
	my $list = $listh->fetchall_arrayref({});
	
	my $uph = database()->prepare_cached("update repeatersignals
                                             set signallevel = ?
                                           where repeaterid = ? and listener = ?");
	my $insh = database()->prepare_cached("insert into repeatersignals (repeaterid, listener, signallevel) values(?, ?, ?)");

	my $level;
	
	foreach my $repeater (@$list) {
		debug("checking repeater: $repeater->{'repeaterid'}");
		if ($level = param("signallevel_$repeater->{'repeaterid'}")) {
			# extract the level
			if ($level eq 'Not Heard') {
				$level = -1;
			} else {
				$level =~ s/.*S(\d).*/$1/;
			}
			debug("  level: $level");
			next if ($level !~ /^-?\d$/);
			
			my $count = $uph->execute($level, $repeater->{'repeaterid'}, session('user'));
			if ($count == 0) {
				# no row exists; insert it
				$insh->execute($repeater->{'repeaterid'}, session('user'), $level);
			}
		}
	}
	
	template 'repeaters/signals' => { list => $list }; 
};



1;
