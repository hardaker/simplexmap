package simplexmap::Constants;

use strict;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw($callsign_regex);

our $callsign_regex = qr/^[a-zA-Z]{1,2}[0-9][a-zA-Z]{1,3}\/?[a-zA-Z]*$/;

1;
