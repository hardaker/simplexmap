package simplexmap;
use Dancer ':syntax';

our $VERSION = '0.1';

use lib 'lib';
use simplexmap::Login;
use simplexmap::Stations;

get '/' => sub {
    template 'index';
};

true;
