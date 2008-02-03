package SimplexMap;

use GeoDB::Utils;
use Data::Dumper;
use IO::File;

use strict;

our $dbh;
our $getconnection;
our $getperson;
our $dbhsigns;
our $getaddrh;
our %opts;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(init_simplexmap export_kml export_graphviz export_csv);

sub init_simplexmap {
    my ($opts) = @_;
    %opts = %$opts;

    # connection db setup
    $dbh = DBI->connect("DBI:SQLite2:dbname=$opts{d}");
    $getconnection = $dbh->prepare("select listener, heard from connections where band = ? and listener <> heard");
    $getperson = $dbh->prepare("select lat, lon from people where callsign = ? or callsign = ?");
    $dbh = DBI->connect("DBI:SQLite2:dbname=$opts->{d}");

    # geographical location setup
    Geo::Coder::US->set_db($opts{'g'});
    $dbhsigns = DBI->connect("DBI:SQLite2:dbname=$opts{H}");
    $getaddrh = $dbhsigns->prepare("select first_name, po_box, street_address, city, state, zip_code from PUBACC_EN where call_sign = ?");
}

########################################
# CSV
#
my $g;

sub get_fh {
    my ($fh) = @_;
    if (ref($fh) eq '') {
	$fh = new IO::File "> $fh";
    }
    return $fh;
}

sub export_csv {
    my ($fh) = get_fh(@_);
    my ($row, $count);


    print $fh "#LISTENER,CANHEAR,MILES\n";

    $getconnection->execute($opts{'b'});
    while ($row = $getconnection->fetchrow_arrayref()) {
	my $dist = calc_distance(get_latlon($row->[0]),get_latlon($row->[1]));
	print $fh "$row->[0],$row->[1],$dist\n";
	$count++;
    }

    $fh->close();

    return $count;
}

########################################
# GraphViz
#
my $g;
sub export_graphviz {
    my $yellow = "#ffff99";                    # not found, not max
    my $red = "#ff8888";                       # not found, max
    my $orange = "#ffbe69";
    my $green = '#99ff99';
    my $count = 0;
    my $row;

    my $fh = get_fh(@_);

    $g = GraphViz->new(node => { fillcolor => $yellow,
				 fontsize => 8,
				 style => 'filled'},
		       #		      edge => { minlen => 100 },
		       no_overlap => 1,
		       epsilon => $opts{'e'},
		       layout => $opts{'l'});

    $getconnection->execute($opts{'b'});
    while ($row = $getconnection->fetchrow_arrayref()) {
	add_edge(@$row);
	$count++;
    }

    print $fh $g->as_png;
    return $count;
}

my (%nodes, %edges);
sub add_edge {
    my @labels = @_;
    if (!exists($nodes{$labels[0]})) {
	$nodes{$labels[0]} = $g->add_node($labels[0], label => $_[0]);
    }
    if ($_[1] && !exists($nodes{$labels[1]})) {
	$nodes{$labels[1]} = $g->add_node($labels[1], label => $_[1]);
    }

    # backwards to show who learned from who
    if ($_[1] && !exists($edges{$labels[1]}{$labels[0]})) {
	$edges{$labels[1]}{$labels[0]} = 1;
	$g->add_edge($nodes{$labels[1]}, $nodes{$labels[0]});
    }
}

########################################
# KML
#
sub export_kml {
    my ($fh) = get_fh(@_);
    my $row;
    my $count = 0;

    start_kml($fh);
    $getconnection->execute($opts{'b'});
    while ($row = $getconnection->fetchrow_arrayref()) {
	export_person($fh, $row->[0]);
	export_person($fh, $row->[1]);
	export_path($fh, $row->[0], $row->[1]);
	$count++;
    }
    end_kml($fh);
    return $count;
}

sub start_kml {
    my ($fh) = @_;
    print $fh '<?xml version="1.0" encoding="utf-8"?>
<kml xmlns="http://earth.google.com/kml/2.0">
<Folder>
  <description>ARES Simplex Map</description>
  <Folder>
    <name>ARES Simplex Map</name>
';
}

sub end_kml {
    my ($fh) = @_;
    print $fh "</Folder>
</Folder>
</kml>
";
}

my %doneperson;
my $unknowncount;

sub export_person {
    my ($fh, $person) = @_;
    $person = uc($person);
    return if (exists($doneperson{$person}));
    $doneperson{$person} = 1;

    my ($lat, $lon) = get_latlon($person);

    print K "
  <Placemark>
    <description>$person</description>
    <name>$person</name>
    <styleUrl>#khStyle652</styleUrl>
    <Point>
      <altitudeMode>clampToGround</altitudeMode>
      <coordinates>$lon,$lat,0</coordinates>
    </Point>
  </Placemark>
";
}

my %donepath;
sub export_path {
    my ($fh, $one, $two) = @_;
    $one = uc($one);
    $two = uc($two);
    return if (exists($donepath{$one}{$two}));
    $donepath{$one}{$two} = 1;

    my ($lat1, $lon1) = get_latlon($one);
    my ($lat2, $lon2) = get_latlon($two);

    print K "
  <Placemark>
    <description>$one to $two</description>
    <name>$one to $two</name>
    <styleUrl>#khStyle652</styleUrl>
    <LineString>
      <tesselate>1</tesselate>
      <coordinates>$lon1,$lat1,0
        $lon2,$lat2,0
      </coordinates>
    </LineString>
  </Placemark>
";
}

my %previous;
sub get_latlon {
    my $person = shift;

    if (exists($previous{$person})) {
	return ($previous{$person}{'lat'}, $previous{$person}{'lon'});
    }

    my ($lat, $lon);
    $getperson->execute(lc($person), $person);
    while (my $prow = $getperson->fetchrow_arrayref()) {
	($lat, $lon) = ($prow->[0], $prow->[1]);
    }
    my ($plat, $plon) = parse_coords($lat, $lon);
#     if ($plat == 0 || $plon == 0) {
# 	$plat = $lat;
# 	$plon = $lon;
#     }

    if ($plat == 0 || $plon == 0 ||
	($plat == 38 && $plon == -121) ||
	$plat !~ /^\d+\.\d+$/ || $plon !~ /^-\d+\.\d+$/) {
	$getaddrh->execute($person);
	my $rows = $getaddrh->fetchall_arrayref();
	my $row = $rows->[$#$rows];  # assume the last is the best

	# XXX: po box
	my @res = Geo::Coder::US->geocode("$row->[2], $row->[3], $row->[4]");
	if ($res[0]{'lat'}) {
	    $plat = $res[0]{'lat'};
	    $plon = $res[0]{'long'};
	} else {
	    print "Warning: unknown lat/lon for address for $person\n  ($row->[2], $row->[3], $row->[4], $row->[5])\n";
	}
    }

    if ($plat == 0 || $plon == 0 ||
	($plat == 38 && $plon == -121) ||
	$plat !~ /^\d+\.\d+$/ || $plon !~ /^-\d+\.\d+$/) {

	print "Warning: unknown lat/lon for $person ($plat, $plon)\n";
	if (exists($previous{$person})) {
	    return ($previous{$person}{'lat'},$previous{$person}{'lon'});
	}
	($plat, $plon) = parse_coords("N38 38.000", "W121 50.000");
#	$plat += $unknowncount * 0.002;
	$plon += $unknowncount * 0.002;
	$unknowncount++;
    }
    $previous{$person}{'lat'} = $plat;
    $previous{$person}{'lon'} = $plon;
    return ($plat, $plon);
}

1;
