package simplexmap::Stations;

use Dancer ':syntax';
use Dancer::Plugin::Database;

get '/stations' => sub {
	my $listh = database()->prepare_cached("select * from locations where locationperson = ?");
	$listh->execute(session('id'));
	my $list = $listh->fetchall_arrayref({});
	
	template 'stations' => { list => $list }; 
};

1;
