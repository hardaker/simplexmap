package simplexmap;
use Dancer ':syntax';

our $VERSION = '0.1';

use lib 'lib';
use simplexmap::Login;
use simplexmap::Stations;
use simplexmap::Repeaters;

get '/' => sub {
    template 'index';
};

true;
