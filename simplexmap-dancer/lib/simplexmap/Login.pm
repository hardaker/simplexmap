package simplexmap::Login;

use Dancer ':syntax';
use Dancer::Plugin::Database;


hook 'before' => sub {
	# if we're not a user and we're not a sensor, force the login page
	if (! session('user') && request->path_info !~ m{^/login}) {
		var requested_path => request->path_info;
		request->path_info('/login');
	} else {
		my $user = session('user') || "none";
		my $sensor = session('sensor') || "none";
	}
};

get '/login' => sub {
	my $failedNote = "";

	$failedNote = "Login Failed; Try again"
	  if (param('failed'));
	
	template 'login' => { failedNote => $failedNote };
};

post '/login' => sub {
	# look for params and authenticate the user
	# ...
	my $user;

	my $dbh = database();
	my $loginh = $dbh->prepare_cached("select * from people
                                        where callsign = ? and password = ?");

	$loginh->execute(param('name'), param('pass'));
	if (my $row = $loginh->fetchrow_arrayref()) {
		session user => $row->{'id'};
		session login => param('name');
	} else {
		return redirect '/login?failed=1';
	}
};

1;
