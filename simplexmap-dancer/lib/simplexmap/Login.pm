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
	  if (param('theyfailed'));
	
	template 'login' => { failedNote => $failedNote };
};

post '/login' => sub {
	# look for params and authenticate the user
	# ...
	my $user;
	
	if ($user) {
		session user_id => $user->id;
	}
};

get '/login' => sub {
	# if a user is present in the session, let him go, otherwise redirect to
	# /login
	if (not session('user_id')) {
		redirect '/login';
	}
};

1;
