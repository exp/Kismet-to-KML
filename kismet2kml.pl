#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  kismet2kml.pl
#
#        USAGE:  ./kismet2kml.pl  
#
#  DESCRIPTION:  Converts kismet gps log files into kml files
#
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Paul Robins (paul@wza.us), 
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  10/03/10 18:38:44
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;
use lib               'lib/perl5';
use Data::Dump        qw/ddx/;
use Math::ConvexHull  qw/convex_hull/;
use XML::Simple;
use XML::Generator;

my $file  = $ARGV[0]  or die "Please specify a filename to read";
(-r $file)            or die "Please ensure the file you specified is readable";

my %waps;

my $gpsin = XMLin($file) or die "Failed to parse input file";

for my $point (@{$gpsin->{'gps-point'}}) {
  # Ignore any points without a full 3d GPS fix
  next unless ($point->{fix}  == 3);

  my $bssid = $point->{bssid};
  
  $waps{$bssid} = {
    points  => [],
    powers  => {},
    ssid    => $bssid } unless ($waps{$bssid});

  my $coords  = [$point->{lat},$point->{lon}];

  push @{$waps{$bssid}->{points}}, $coords;
  $waps{$bssid}->{powers}->{$coords}  = $point->{signal};
}

my $gen = XML::Generator->new(
  pretty    => 2,
);

my @elements;
for my $wap (keys %waps) {
  $waps{$wap}->{hull} = convex_hull($waps{$wap}->{points});
  my $xml = $gen->Placemark({id => $wap},
    $gen->name($wap),
    $gen->description('testing'),
    $gen->Point(
      $gen->extrude('1'),
      $gen->altitudeMode('relativeToGround'),
      $gen->coordinates($waps{$wap}->{points}[0]->[1] ."," . $waps{$wap}->{points}[0]->[0] . ",2"),
    ),
  );

  push @elements, $xml;
}

open (my $out,'>','test.kml');

print $out '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
print $out $gen->kml(['http://www.opengis.net/kml/2.2'],
  $gen->Folder(
    $gen->name('Kismet GPS'),
    @elements,
  )) . "\n";

close $out;

print '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
print $gen->kml(['http://www.opengis.net/kml/2.2'],
  $gen->Folder(
    $gen->name('Kismet GPS'),
    @elements,
  )) . "\n";
