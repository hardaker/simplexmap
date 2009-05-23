package SimplexMap;

use lib qw(../perl/share/perl/5.8.8);
use lib qw(../geoqo-1.01);

use GeoDB::Utils;
use Data::Dumper;
use IO::File;
use Data::Dumper;
use Geo::Coder::US;
use CGI qw(escapeHTML);
#use GraphViz;

use strict;

our $dbh;
our $getconnection;
our $getperson;
our $dbhsigns;
our $getaddrh;
our %opts;
our $calldetails;
our $hdh;
our $vdh;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(init_simplexmap export_kml export_graphviz export_csv
		 get_one get_many get_one_value debug);

sub init_simplexmap {
    my ($opts) = @_;
    %opts = %$opts;

    # connection db setup
    if ($opts{'d'} && -f $opts{'d'}) {
	$dbh = DBI->connect("DBI:SQLite:dbname=$opts{d}");
	debug("opening $opts{d}\n");
	$getconnection =
	  $dbh->prepare("select receiver.callsign, sender.callsign,
                                comment, rating from connections
                      left join people as receiver
                             on receiver.id = listener
                      left join people as sender
                             on sender.id = heard
                          where eventid = ?
                            and listener <> heard");
	$getperson =
	  $dbh->prepare("select locationtype,
                                locationlat, locationlon,
                                locationaddress, locationcity, locationstate,
                                locationzip,
                                locationname, eventpersondetails
                           from locations
                      left join people
                             on eventperson = id
                      left join eventmembers
                             on locationid = eventpersonlocation
                          where callsign = ?
                            and eventid = ?");
    }

    # geographical location setup
    Geo::Coder::US->set_db($opts{'g'}) if ($opts{'g'});

    if ($opts{'H'} && -f $opts{'H'}) {
	$dbhsigns = DBI->connect("DBI:SQLite:dbname=$opts{H}");
	$getaddrh =
	  $dbhsigns->prepare("select first_name, po_box, street_address, 
                                     city, state, zip_code
                                from PUBACC_EN
                               where call_sign = ?");
	$calldetails = $dbhsigns->prepare("select first_name, street_address, city, state, zip_code, frn, applicant_type_code, unique_system_identifier, last_name from PUBACC_EN where unique_system_identifier = ?");
	$hdh = $dbhsigns->prepare("select license_status, grant_date, expired_date, unique_system_identifier from PUBACC_HD where call_sign = ? order by unique_system_identifier desc limit 1");
	$vdh = $dbhsigns->prepare("select unique_system_identifier from PUBACC_VC where callsign_requested = ? order by unique_system_identifier desc limit 1");
    }
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


    print $fh "#LISTENER,CANHEAR,MILES,SIGNAL,COMMENT\n";

    debug("getting connections: eventid=$opts{'b'}\n");
    $getconnection->execute($opts{'b'});
    while ($row = $getconnection->fetchrow_arrayref()) {
	my ($lat1, $lon1) = get_latlon($row->[0], $opts{'b'});
	my ($lat2, $lon2) = get_latlon($row->[1], $opts{'b'});
	
	my $dist = calc_distance($lat1, $lon1, $lat2, $lon2);
	print $fh "$row->[0],$row->[1],$dist,$row->[3],\"$row->[2]\"\n";
	$count++;
    }

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
my %paths;
sub export_kml {
    my ($fh) = get_fh(@_);
    my $row;
    my $count = 0;

    start_kml($fh);
    $getconnection->execute($opts{'b'});
    print $fh "  <Folder>\n    <name>Stations</name>\n";
    while ($row = $getconnection->fetchrow_arrayref()) {
	export_person($fh, $row->[0]);
	export_person($fh, $row->[1]);
	export_path($fh, $row->[0], $row->[1], $row->[3], $row->[2]);
	$count++;
    }
    print $fh "  </Folder>\n  <Folder>\n    <name>Connections</name>\n";

    foreach my $person (keys(%paths)) {
	print $fh "<Folder>
	  <name>Connections: " . escapeHTML($person) . "</name>
  $paths{$person}
  </Folder>
";
    }

    end_kml($fh);
    return $count;
}

sub start_kml {
    my ($fh) = @_;
    print $fh '<?xml version="1.0" encoding="utf-8"?>
<kml xmlns="http://earth.google.com/kml/2.0">
<Folder>
  <name>Connection Map</name>
  <Style id="yred">
    <LineStyle>
      <width>2</width>
      <color>7f0000ff</color>
    </LineStyle>
  </Style>
  <Style id="ygreen">
    <LineStyle>
      <width>2</width>
      <color>7f00ff00</color>
    </LineStyle>
  </Style>
  <Style id="yblue">
    <LineStyle>
      <width>2</width>
      <color>7fff0000</color>
    </LineStyle>
  </Style>
  <Style id="ypurple">
    <LineStyle>
      <width>2</width>
      <color>7fb000b0</color>
    </LineStyle>
  </Style>
  <Style id="yyellow">
    <LineStyle>
      <width>2</width>
      <color>7f00b0b0</color>
    </LineStyle>
  </Style>
  <Style id="ymarine">
    <LineStyle>
      <width>2</width>
      <color>7fb0b000</color>
    </LineStyle>
  </Style>
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

    my $eventdetails = get_one($getperson, $person, $opts{'b'});
    my $fccdat = get_fcc_data($person);
    my ($lat, $lon, $location) = get_latlon($person, $opts{'b'});

    print $fh "
  <Placemark>
    <name>" . escapeHTML("$person: $fccdat->[0]") . "</name>
    <description><![CDATA[<pre>" . escapeHTML("$person: $fccdat->[0]
Location $eventdetails->[7]: $location
$eventdetails->[8]
") . "</pre>]]></description>
    <styleUrl>#yblue</styleUrl>
    <Point>
      <altitudeMode>clampToGround</altitudeMode>
      <coordinates>$lon,$lat,0</coordinates>
    </Point>
  </Placemark>
";
}

my %donepath;
sub export_path {
    my ($fh, $one, $two, $signal, $comment) = @_;
    $one = uc($one);
    $two = uc($two);
    return if (exists($donepath{$one}{$two}));
    $donepath{$one}{$two} = 1;

    my ($lat1, $lon1) = get_latlon($one, $opts{'b'});
    my ($lat2, $lon2) = get_latlon($two, $opts{'b'});

    my $distance = calc_distance($lat1, $lon1, $lat2, $lon2);

    my $key;
    if ($opts{'groupby'} eq 'From') {
	$key = $two;
    } else {
	$key = $one;
    }

    my $style = "#yblue";
    $style = $opts{'styles'}{$key} if (exists($opts{'styles'}{$key}));
    $paths{$key} .= "
  <Placemark>
    <name>" . escapeHTML("$one heard $two") . "</name>
    <description><![CDATA[<pre>" . escapeHTML("signal: $signal\ndistance: $distance\n$comment") . "</pre>]]></description>
    <styleUrl>$style</styleUrl>
    <LineString>
      <tesselate>1</tesselate>
      <coordinates>$lon1,$lat1,0
        $lon2,$lat2,0
      </coordinates>
    </LineString>
  </Placemark>
";
}

sub export_all_paths {
}

my %previous;
sub get_latlon {
    my ($person, $eventid) = @_;

    if (exists($previous{$person})) {
	return ($previous{$person}{'lat'}, $previous{$person}{'lon'});
    }

    my ($lat, $lon);
    $getperson->execute(uc($person), $opts{'b'});

    my $prow = $getperson->fetchrow_arrayref();
    my ($plat, $plon, $status);

    if (!$prow && $getaddrh) {
	# doesn't exist in the DB, force to address untill someone
	# fills in more appropriate info.
	debug("No entry for $person\n");
	$prow->[0] = 'Address';
	$status = "Assumed at registered FCC Address";
	
	# pull the address from the FCC database
	my $dat = get_fcc_data($person);
	$prow->[3] = $dat->[1];
	$prow->[4] = $dat->[2];
	$prow->[5] = $dat->[3];
	$prow->[6] = $dat->[4];
    }

    #
    # lat/lon directly specified
    #
    if ($prow->[0] eq 'Coordinates') {
	($lat, $lon) = ($prow->[0], $prow->[1]);
	($lat, $lon) = parse_coords($lat, $lon);
	if ($lat != 0) {
	    $previous{$person}{'lat'} = $lat;
	    $previous{$person}{'lon'} = $lon;
	    return ($lat, $lon, "From Entered Coordinates");
	}
    }

    #
    # address specified
    #
    if ($prow->[0] eq 'Address') {
	if ($opts{'g'}) {

	    # XXX deal with PO boxes

	    debug("looking up $person using $prow->[3], $prow->[4], $prow->[5], $prow->[6]\n");
	    my @res = Geo::Coder::US->geocode("$prow->[3], $prow->[4], $prow->[5], $prow->[6]");
	    if ($res[0]{'lat'}) {
		$previous{$person}{'lat'} = $res[0]{'lat'};
		$previous{$person}{'lon'} = $res[0]{'long'};
		debug("  result: $res[0]{'lat'}, $res[0]{'long'} $status\n");
		$status = "Entered Physical Address" if (!$status);
		return ($res[0]{'lat'}, $res[0]{'long'}, $status);
	    } else {
		debug("Warning: unknown lat/lon for address for $person\n   $prow->[3]\n");
	    }
	}
    }

    # uh oh...  if we got here, it's because we failed to get a real location...
    debug("Warning: unknown lat/lon for $person ($plat, $plon)\n");

    # XXX
    ($lat, $lon) = parse_coords("N38 38.000", "W121 50.000");

    #	$lat += $unknowncount * 0.002;
    $lon += $unknowncount * 0.002;
    $unknowncount++;

    $previous{$person}{'lat'} = $lat;
    $previous{$person}{'lon'} = $lon;
    return ($lat, $lon, "Randomly generated since it was unknown");
}

########################################
# FCC Data
#
sub get_fcc_data {
    return if (!$dbhsigns);
    my $callsign = shift;
    $callsign = uc($callsign);
    my @signs;

    use Data::Dumper;;
    my $rows = get_many($hdh, $callsign);
    #print Dumper($rows);
    push @signs, $rows->[$#$rows][3] if ($#$rows != -1);
    $rows = get_many($vdh, $callsign);
    #print Dumper($rows);
    push @signs, $rows->[$#$rows][0] if ($#$rows != -1);

    return [] if ($#signs == -1);

    my $row = get_one($calldetails, $signs[$#signs]);
#    debug("grabbed: $callsign -> $row->[0]\n");
    return $row;
}

########################################
# SQL HELP
sub get_one {
    my $sth = shift;
    debug("here: " . join(",",caller()) . "\n");
    $sth->execute(@_);
    my $row = $sth->fetchrow_arrayref();
    $sth->finish();
    return $row;
}

sub get_one_value {
    my $row = get_one(@_);
    return $row->[0];
}

sub get_many {
    my $sth = shift;
    debug("here: " . join(",",caller()) . "\n");
    $sth->execute(@_);
    my $rows = $sth->fetchall_arrayref();
    $sth->finish();
    return $rows;
}

sub debug {
    if ($opts{'debug'}) {
	print STDERR @_;
    }
}

1;

