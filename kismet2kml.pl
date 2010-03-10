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
use XML::Bare;

my $file  = $ARGV[0]  or die "Please specify a filename to read";
(-r $file)            or die "Please ensure the file you specified is readable";

my %waps;

open(my $fh,'<',$file)  or die "Failed to open file";
while (<$fh>) {
  next unless (/gps-point/);

  my $xml   = new XML::Bare(text  => $_);
  my $tree  = $xml->parse;
  my $gps   = $tree->{'gps-point'};
  my $bssid = $gps->{bssid}->{value};

  next unless ($gps->{fix}->{value} == 3);

  $waps{$bssid} = {power => {}, points => []} unless ($waps{$bssid});

  my $coords    = [$gps->{lat}->{value},$gps->{lon}->{value}];

  $waps{$bssid}->{power}->{$coords}  = $gps->{signal}->{value};
  push @{$waps{$bssid}->{points}},$coords;
}

close($fh);

for my $wap (keys %waps) {
  print "Processing WAP $wap\n";
  
  my $hull  = convex_hull($waps{$wap}->{points});
  for my $point (@{$hull}) {
    next unless $point;

    ddx($point);
    ddx($waps{$wap}->{power}->{$point});
  }
}
