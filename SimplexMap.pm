package SimplexMap;

use GeoDB::Utils;

use strict;

our $dbh;
our $getconnection;
our $getperson;
our $dbhsigns;
our $getaddrh;
our %opts;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(init_simplexmap export_kml);


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

sub export_kml {
    my ($file) = @_;
    my $row;
    my $count = 0;

    start_kml();
    $getconnection->execute($opts{'b'});
    while ($row = $getconnection->fetchrow_arrayref()) {
	export_person($row->[0]);
	export_person($row->[1]);
	export_path($row->[0], $row->[1]);
	$count++;
    }
    end_kml();
    return $count;
}

sub start_kml {
    open(K,">$opts{k}") if ($opts{'k'});
    print K '<?xml version="1.0" encoding="utf-8"?>
<kml xmlns="http://earth.google.com/kml/2.0">
<Folder>
  <description>ARES Simplex Map</description>
  <Folder>
    <name>ARES Simplex Map</name>
';
}

sub end_kml {
    print K "</Folder>
</Folder>
</kml>
";
    close(K);
}

my %doneperson;
my $unknowncount;

sub export_person {
    return if (!$opts{'k'});
    my $person = uc($_[0]);
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
    return if (!$opts{'k'});
    my ($one, $two) = (uc($_[0]), uc($_[1]));
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
	my @res = Geo::Coder::US->geocode("$row->[2], $row->[3], $row->[4], $row->[5]");
	if ($res[0]{'lat'}) {
	    $plat = $res[0]{'lat'};
	    $plon = $res[0]{'lon'};
	}
    }

    if ($plat == 0 || $plon == 0 ||
	($plat == 38 && $plon == -121) ||
	$plat !~ /^\d+\.\d+$/ || $plon !~ /^-\d+\.\d+$/) {

	if (exists($previous{$person})) {
	    return ($previous{$person}{'lat'},$previous{$person}{'lon'});
	}
	($plat, $plon) = parse_coords("N38 38.000", "W121 50.000");
#	$plat += $unknowncount * 0.002;
	$plon += $unknowncount * 0.002;
	$unknowncount++;
	$previous{$person}{'lat'} = $plat;
	$previous{$person}{'lon'} = $plon;
    }
    return ($plat, $plon);
}

1;
