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
use Math::NumberCruncher;
use XML::Simple;
use XML::Generator;

my $prefix  = $ARGV[0]  or die "Please specify a prefix for gps and xml files";
(-r "$prefix.gps" && -r "$prefix.xml") or die "Either the gps or xml file is unreadable";

my ($minpower,$maxpower)  = undef;
my %waps;

sub norm_power {
  my $in  = shift;

  $in     += abs($minpower);
  $in     /= ($maxpower+abs($minpower))/5;
  $in     += 1;

  return $in;
}

my $gpsin = XMLin("$prefix.gps") or die "Failed to parse gps input file";
#my $xmlin = XMLin("$prefix.xml") or die "Failed to parse xml input file";

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
  my @points  = sort {$a->{lat} <=> $b->{lat} ||
                      $a->{lon} <=> $b->{lon}} @{$waps{$wap}->{points}};

  my @sorted;
  my %pointrefs;
  for my $point (@points) {
    my $coordref  = [$point->{lat},$point->{lon}];

    if (@sorted && $sorted[$#sorted]->[0] == $point->{lat} && $sorted[$#sorted]->[1] == $point->{lon}) {
      # Multiple points at the same location may have different power levels
      if ($pointrefs{$point}->{signals}) {
        push @{$sorted[$#sorted]->{signals}}, $point->{signal};
        $sorted[$#sorted]->{signal} = Math::NumberCruncher::Median($sorted[$#sorted]->{signals});
      } else {
        $pointrefs{$sorted[$#sorted]}->{signals} = [$pointrefs{$sorted[$#sorted]}->{signal}];
      }
      next;
    };

    push @sorted,$coordref;
    $pointrefs{$coordref} = $point;
  }

  my $hull  = convex_hull(\@sorted);

  my $hullpoints;
  my @geometry;
  for my $point (@{$hull}) {
    next unless ($point);
    push @geometry, $gen->Point(
      $gen->extrude('1'),
      $gen->altitudeMode('relativeToGround'),
      $gen->coordinates($pointrefs{$point}->{lon} ."," . $pointrefs{$point}->{lat} . "," . norm_power($pointrefs{$point}->{signal})),
    );
  }

  my $xml   = $gen->Placemark({id => $wap},
    $gen->name($wap),
    $gen->description('testing'),
    $gen->MultiGeometry(
      @geometry,
    ),
  );

  push @elements, $xml;
}

print '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
print $gen->kml(['http://www.opengis.net/kml/2.2'],
  $gen->Folder(
    $gen->name('Kismet GPS'),
    @elements,
  )) . "\n";
