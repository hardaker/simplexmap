package simplexmap::Login;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::DataFormValidator;
use Data::FormValidator::Constraints qw(:closures);
use MIME::Base64;
use Mail::Sender;
use Crypt::OpenSSL::Random;
use Digest::SHA qw(sha256_hex);

hook 'before' => sub {
	# if we're not a user and we're not a sensor, force the login page
	if (! session('callsign') && 
	    request->path_info !~ m{^/login} && 
	    request->path_info !~ m{^/validate} && 
	    request->path_info !~ m{^/signup}) {
		var requested_path => request->path_info;
		request->path_info('/login');
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
                                        where callsign = ?");

	$loginh->execute(uc(param('callsign')));
	if (my $row = $loginh->fetchrow_hashref()) {
		$loginh->finish;

		my $salt = $row->{'salt'};
		if (get_salted_password($salt, param('password')) ne $row->{'password'}) {
			debug("here: " . param('password') . " ne $row->{'password'}");
			return redirect '/login?failed=1';
		}

		debug($row);
		# make sure they clicked on the link
		if (length($row->{'validation'}) > 0) {
			return template 'login' => {notvalidated => 1};
		}
		session user => $row->{'id'};
		session callsign => uc(param('callsign'));
	} else {
		$loginh->finish;
		debug("user not found: " . uc(param('callsign')));
		return redirect '/login?failed=1';
	}
	redirect '/';
};

get '/signup' => sub {
	template 'signup';
};

post '/signup' => sub {

	my $results = 
	  dfv({ required => ['firstname', 'lastname', 'callsign', 'email', 'password'],
	        filters => 'trim',
	        constraint_methods => 
	        {
	         firstname      => qr/^[a-zA-Z]+$/,
	         lastname       => qr/^[a-zA-Z]+$/,
	         callsign       => qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}$/,
	         email  		=> email(),
	         password       => FV_min_length(6),
	        }
	      });

	if ($results->has_invalid || $results->has_missing) {
		return template 'signup' => { messages => $results->msgs };
	}

	my $vals = $results->valid;
	$vals->{'callsign'} = uc($vals->{'callsign'});

	my $dbh = database();

	# see if they already have an account
	my $sth = $dbh->prepare_cached("select * from people
                                     where callsign = ?");
	$sth->execute($vals->{'callsign'});
	if ($sth->fetchrow_arrayref()) {
		# they already have an account
		return template 'signup' => 
		  { messages => { callsign => 'An account with this callsign already exists' }}
	}

	# put them into the db
	my $insh = $dbh->prepare_cached("insert into people (callsign, firstname, lastname, salt, password, email, validation)
                                                  values(?, ?, ?, ?, ?, ?, ?)");
	my $salt = get_salt();
	my $verifyCode = get_salt();
	$insh->execute($vals->{'callsign'}, $vals->{'firstname'}, $vals->{'lastname'},
	               $salt, get_salted_password($salt, $vals->{'password'}),
	               $vals->{'email'}, $verifyCode);

	# send email
	my $sender = new Mail::Sender { smtp => 'dawn.hardakers.net',
	                                  from => "wes\@ws6z.com"};
	my $ret = 
	$sender->MailMsg({ to => $vals->{'email'},
	                   subject => 'validation link for the simplex mapping site',
	                   msg =>
"
Someone has created an account on the simplex mapping system using this email
address and a callsign of '$vals->{callsign}'.  Hopefully this was you!
To validate your address and complete your account, please click on this link:

  http://localhost:4000/validate?code=$verifyCode&callsign=$vals->{callsign}

"
	                 });	

	if (ref($ret) ne 'Mail::Sender') {
		warn("mail::sender failed: $ret -- $sender->{error_msg}"); 
		my $delh = $dbh->prepare_cached("delete from people where callsign = ?");
		$delh->execute($vals->{'callsign'});
	}

	template 'waiting_verification';
};

any '/validate' => sub {
	
	my $sth = database()->prepare_cached("select * from people
                                           where callsign = ? and validation = ?");
	$sth->execute(uc(param('callsign')), param('code'));

	debug("validating: " . (param('callsign') || "no call") . " with " . (param('code') || 'no val'));

	if (my $row = $sth->fetchrow_hashref()) {
		# success
		my $uph = database()->prepare_cached("update people set validation = ? where callsign = ?");
		$uph->execute(param('code'), uc(param('callsign')));

		# set their session
		session user => $row->{'id'};
		session callsign => uc(param('callsign'));

		return redirect '/';
	}

	# failure
	template 'waiting_verification' => { failed => 1 };
};


sub get_salt {
	my $salt = encode_base64(Crypt::OpenSSL::Random::random_bytes(10));
	chomp($salt);
	return $salt;
}

sub get_salted_password {
	my ($salt, $pw) = @_;
	return sha256_hex($salt . $pw);
}

1;
