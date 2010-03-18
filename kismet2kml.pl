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

my ($minpower,$maxpower)  = undef;
# Older kismet files set signal to 0 if the card does not provide it
# newer files appear to not set the signal at all
my $seensignal  = 0;
my %waps;

my $prefix  = $ARGV[0]  or die "Please specify a prefix for gps and xml files";

my ($gpsin,$xmlin);
if (-r "$prefix.gps" && -r "$prefix.xml") {
  $gpsin = XMLin("$prefix.gps") or die "Failed to parse gps input file";
  $xmlin = XMLin("$prefix.xml") or die "Failed to parse xml input file";
  parse_gps();
} elsif (-r "$prefix.gpsxml" && -r "$prefix.netxml") {
  $gpsin = XMLin("$prefix.gpsxml") or die "Failed to parse gps input file";
  $xmlin = XMLin("$prefix.netxml") or die "Failed to parse xml input file";
  parse_gpsxml();
} else {
  die "Either the gps or xml file is unreadable";
}

sub norm_power {
  my $in  = shift;

  return 1 unless ($seensignal);

  $in     += abs($minpower);
  $in     /= ($maxpower+abs($minpower))/5;
  $in     += 1;

  return $in;
}

sub parse_gps {
  for my $network (@{$xmlin->{'wireless-network'}}) {
    my $wap = {};
    $wap->{ESSID}   = $network->{SSID};
    $wap->{BSSID}   = $network->{BSSID};
    $wap->{Channel} = $network->{channel};
    if (ref($network->{encryption})  ne 'ARRAY') {
      $wap->{Encryption}  = $network->{encryption};
    } else {
      $wap->{Encryption}  = join(', ',@{$network->{encryption}});
    }
  
    if ($network->{'wireless-client'}) {
      if (ref($network->{'wireless-client'})  eq 'HASH') {
        $wap->{Clients} = 1;
      } else {
        $wap->{Clients} = scalar @{$network->{'wireless-client'}};
      }
    }
    $wap->{Clients} //= 0;
  
    $waps{$network->{BSSID}}  = {desc => $wap};
  }
}

sub parse_gpsxml {
  for my $network (@{$xmlin->{'wireless-network'}}) {
    next unless (defined($network->{SSID}));

    my $wap = {};
    $wap->{ESSID}   = $network->{SSID}->{essid}->{content} if ($network->{SSID}->{essid}->{content});
    $wap->{BSSID}   = $network->{BSSID};
    $wap->{Channel} = $network->{channel};

    if (ref($network->{SSID}->{encryption}) ne 'ARRAY') {
      $wap->{Encryption}  = $network->{SSID}->{encryption};
    } else {
      $wap->{Encryption}  = join(', ',@{$network->{SSID}->{encryption}});
    }

    if ($network->{'wireless-client'}) {
      if (ref($network->{'wireless-client'})  eq 'HASH') {
        $wap->{Clients} = 1;
      } else {
        $wap->{Clients} = scalar @{$network->{'wireless-client'}};
      }
    }
    $wap->{Clients} //= 0;
  
    $waps{$network->{BSSID}}  = {desc => $wap};
  }
}

print STDERR "Beginning GPS point scan\n";
for my $point (@{$gpsin->{'gps-point'}}) {
  # Ignore any points without a full 3d GPS fix
  next unless ($point->{fix}  == 3);
  # Ignore points that aren't APs
  next unless ($waps{$point->{bssid}});

  my $bssid = $point->{bssid};

  $seensignal = 1 if ($point->{signal} && $point->{signal}  != 0);

  if ($point->{signal}) {
    $minpower = $point->{signal} unless ($point->{signal} == 0 || defined($minpower) && $minpower <= $point->{signal});
    $maxpower = $point->{signal} unless ($point->{signal} == 0 || defined($maxpower) && $maxpower >= $point->{signal});
  }

  $waps{$bssid} = {
    points  => [],
    ssid    => $bssid } unless ($waps{$bssid});

  $waps{$bssid}->{time} = $point->{'time-sec'} unless (defined($waps{$bssid}->{time}) && $waps{$bssid}->{time} >= $point->{'time-sec'});

  push @{$waps{$bssid}->{points}}, $point;
}
print STDERR "Finished GPS point scan\n";

# This is the path, not a genuine SSID
my $path  = delete($waps{'GP:SD:TR:AC:KL:OG'});

my $gen = XML::Generator->new(
  pretty    => 2,
  escape    => 'even-entities',
);

my @elements;
print STDERR "Beginning WAP calculations\n";
for my $wap (sort {$waps{$a}->{time} <=> $waps{$b}->{time}} keys %waps) {
  my @sorted  = sort {$a->{lat} <=> $b->{lat} ||
                      $a->{lon} <=> $b->{lon}} @{$waps{$wap}->{points}};

  my @points;
  for my $point (@sorted) {
    if ($points[$#points] &&  $points[$#points]->{lat} == $point->{lat} &&
                              $points[$#points]->{lon} == $point->{lon}) {
      next unless ($point->{signal} && $point->{signal} != 0);
      # Multiple points at the same location may have different power levels
      push @{$points[$#points]->{signals}}, $point->{signal};
      $points[$#points]->{signal} = Math::NumberCruncher::Median($points[$#points]->{signals});
      next;
    };

    $point->{signals} = [$point->{signal}];
    push @points,$point;
  }

  my @geometry;
  for my $point (@points) {
    next unless ($point);
    push @geometry, $gen->Point(
      $gen->extrude('1'),
      $gen->altitudeMode('relativeToGround'),
      $gen->coordinates($point->{lon} .",". $point->{lat} .",". norm_power($point->{signal})),
    );
  }

  my $id;
  if ($waps{$wap}->{desc}->{ESSID}) {
    $id = $waps{$wap}->{desc}->{ESSID};
  } else {
    $id = $wap;
  }

  my @description = map {"$_: " . $waps{$wap}->{desc}->{$_} ."<br>\n"} grep {defined($waps{$wap}->{desc}->{$_})} keys %{$waps{$wap}->{desc}};

  my $xml   = $gen->Placemark({id => $id},
    $gen->name($id),
    $gen->description(
      $gen->xmlcdata(@description),
    ),
    $gen->MultiGeometry(
      @geometry,
    ),
  );

  push @elements, $xml;
}
print STDERR "Finished WAP calculations\n";
print STDERR "Printing KML\n";
print '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
print $gen->kml(['http://www.opengis.net/kml/2.2'],
  $gen->Folder(
    $gen->name('Kismet GPS'),
    @elements,
  )) . "\n";
print STDERR "Done\n";
