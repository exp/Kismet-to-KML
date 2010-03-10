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

my $file  = $ARGV[0]  or die "Please specify a filename to read";
(-r $file)            or die "Please ensure the file you specified is readable";

my %waps;

my $xml = XMLin($file) or die "Failed to parse input file";

for my $point (@{$xml->{'gps-point'}}) {
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

for my $wap (keys %waps) {
  print "Processing WAP $wap\n";
  
  my $hull  = convex_hull($waps{$wap}->{points});
}
