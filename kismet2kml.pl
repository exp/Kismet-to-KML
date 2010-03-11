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

my $minpower  = 10;
my $maxpower  = -100000;
my %waps;

sub norm_power {
  my $in  = shift;

  $in     += abs($minpower);
  $in     /= ($maxpower+abs($minpower))/5;
  $in     += 1;

  return $in;
}

my $gpsin = XMLin($file) or die "Failed to parse input file";

for my $point (@{$gpsin->{'gps-point'}}) {
  # Ignore any points without a full 3d GPS fix
  next unless ($point->{fix}  == 3);

  my $bssid = $point->{bssid};
  
  $minpower = $point->{signal} unless ($point->{signal} == 0 || defined($minpower) && $minpower <= $point->{signal});
  $maxpower = $point->{signal} unless ($point->{signal} == 0 || defined($maxpower) && $maxpower >= $point->{signal});

  $waps{$bssid} = {
    points  => [],
    ssid    => $bssid } unless ($waps{$bssid});

  $waps{$bssid}->{time} = $point->{'time-sec'} unless (defined($waps{$bssid}->{time}) && $waps{$bssid}->{time} >= $point->{'time-sec'});

  push @{$waps{$bssid}->{points}}, $point;
}

# This is the path, not a genuine SSID
my $path  = delete($waps{'GP:SD:TR:AC:KL:OG'});

my $gen = XML::Generator->new(
  pretty    => 2,
);

my @elements;
for my $wap (sort {$waps{$a}->{time} <=> $waps{$b}->{time}} keys %waps) {
  # Sort the points by time, this might be pointless
  my @points  = sort {$a->{'time-sec'} <=> $b->{'time-sec'}} @{$waps{$wap}->{points}};

  my @sorted;
  my %pointrefs;
  COORD: for my $point (@points) {
    my $coordref  = [$point->{lat},$point->{lon}];

    for my $coord (@sorted) {
      next COORD if ($coord->[0] == $point->{lat} && $coord->[1] == $point->{lon});
    }

    push @sorted,$coordref;
    $pointrefs{$coordref} = $point;
  }

  my $hull  = convex_hull(\@sorted);

  my $hullpoints;
  my $pointcount  = 0;
  for my $point (@{$hull}) {
    next unless ($point);
    $pointcount++;
    $hullpoints .= $point->[1] . "," . $point->[0] . "," . norm_power($pointrefs{$point}->{signal}) . "\n";
  }
  $hullpoints .= $hull->[0]->[1] . "," . $hull->[0]->[0] . "," . norm_power($pointrefs{$hull->[0]}->{signal}) . "\n";

  my $geometry;
  if ($pointcount <= 3) {
    $geometry = $gen->Point(
      $gen->extrude('1'),
      $gen->altitudeMode('relativeToGround'),
      $gen->coordinates($waps{$wap}->{points}[0]->{lon} ."," . $waps{$wap}->{points}[0]->{lat} . ",8"),
    );
  } else {
    print STDERR "Generating convex hull for WAP $wap with " . scalar @{$hull} . " points\n";
    $geometry = $gen->MultiGeometry(
      $gen->Point(
        $gen->extrude('1'),
        $gen->altitudeMode('relativeToGround'),
        $gen->coordinates($waps{$wap}->{points}[0]->{lon} ."," . $waps{$wap}->{points}[0]->{lat} . ",8"),
      ),
      $gen->Polygon({id=>$wap},
        $gen->extrude('1'),
        $gen->altitudeMode('relativeToGround'),
        $gen->outerBoundaryIs(
          $gen->LinearRing(
            $gen->coordinates($hullpoints),
          ),
        ),
      ),
    );
  }

  my $xml   = $gen->Placemark({id => $wap},
    $gen->name($wap),
    $gen->description('testing'),
    $geometry,
  );

  push @elements, $xml;
}

print '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
print $gen->kml(['http://www.opengis.net/kml/2.2'],
  $gen->Folder(
    $gen->name('Kismet GPS'),
    @elements,
  )) . "\n";
