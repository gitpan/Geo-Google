=head1 NAME

Geo::Google - Perform geographical queries using Google Maps

=head1 SYNOPSIS

  use strict;
  use Data::Dumper;
  use Geo::Google;

  #My office
  my $gonda_addr = '695 Charles E Young Dr S, Westwood, CA 90024';
  #Stan's Donuts
  my $stans_addr = '10948 Weyburn Ave, Westwood, CA 90024';

  #Instantiate a new Geo::Google object.
  my $geo = Geo::Google->new();

  #Create Geo::Google::Location objects.  These contain
  #latitude/longitude coordinates, along with a few other details
  #about the locus.
  my ( $gonda ) = $geo->location( address => $gonda_addr );
  my ( $stans ) = $geo->location( address => $stans_addr );
  print $gonda->latitude, " / ", $gonda->longitude, "\n";
  print $stans->latitude, " / ", $stans->longitude, "\n";

  #Create a Geo::Google::Path object.
  my ( $donut_path ) = $geo->path($gonda,$stans);

  #A path contains a series of Geo::Google::Segment objects with
  #text labels representing turn-by-turn driving directions between
  #the two loci.
  my @segments = $donut_path->segments();

  #This is the human-readable directions for the first leg of the
  #journey.
  print $segments[0]->text(),"\n";

  #Geo::Google::Segment objects contain a series of
  #Geo::Google::Location objects -- one for each time the segment
  #deviates from a straight line to the end of the segment.
  my @points = $segments[1]->points;
  print $points[0]->latitude, " / ", $points[0]->longitude, "\n";

  #Now how about some coffee nearby?
  my @coffee = $geo->near($stans,'coffee');
  #Too many.  How about some Coffee Bean & Tea Leaf?
  @coffee = grep { $_->title =~ /Coffee.*?Bean/i } @coffee;

  #Still too many.  Let's find the closest with a little trig and
  #a Schwartzian transform
  my ( $coffee ) = map { $_->[1] }
                   sort { $a->[0] <=> $b->[0] }
                   map { [ sqrt(
                            ($_->longitude - $stans->longitude)**2
                              +
                            ($_->latitude - $stans->latitude)**2
                           ), $_ ] } @coffee;

=head1 DESCRIPTION

Geo::Google provides access to the map data used by the popular
L<Google Maps|http://maps.google.com> web application.

=head2 WHAT IS PROVIDED

=over

=item Conversion of a street address to a 2D Cartesian point
(latitude/longitude)

=item Conversion of a pair of points to a multi-segmented path of
driving directions between the two points.

=item Querying Google's "Local Search" given a point and one or more
query terms.

=back

=head2 WHAT IS NOT PROVIDED

=over

=item Documentation of the Google Maps map data XML format

=item Documentation of the Google Maps web application API

=item Functionality to create your own Google Maps web page.

=back

=head1 AUTHOR

Allen Day <allenday@ucla.edu>

Copyright (c) 2004-2005 Allen Day. All rights reserved. This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 BUGS / TODO

Report documentation and software bugs to the author, or better yet,
send a patch.  Known bugs/issues:

=over

=item Polyline decoding needs to be cleaned up. 

=item Lack of documentation.

=back

=head1 SEE ALSO

  http://maps.google.com
  http://www.google.com/apis/maps/
  http://libgmail.sourceforge.net/googlemaps.html

=cut

package Geo::Google;
use strict;
use warnings;
our $VERSION = '0.01';

#this gets a javascript page containing map XML
use constant LQ => 'http://maps.google.com/maps?output=js&q=%s';

#this gets a javascript page containing map XML.  special for "nearby" searches
use constant NQ => 'http://maps.google.com/maps?output=js&near=%s&q=%s';

#used in polyline codec
use constant END_OF_STREAM => 9999;

use Data::Dumper;
use Digest::MD5 qw( md5_hex );
use LWP::Simple;
use URI::Escape;
use XML::DOM;
use XML::DOM::XPath;
use Geo::Google::Location;
use Geo::Google::Path;
use Geo::Google::Segment;

sub version { return $VERSION }

=head1 CONSTRUCTOR

=cut

=head2 new()

 Usage    : my $geo = Geo::Google->new();
 Function : constructs and returns a new Geo::Google object
 Returns  : a Geo::Google object
 Args     : n/a

=cut

sub new {
  return bless {}, __PACKAGE__;
}

=head1 OBJECT METHODS

=cut

=head2 error()

 Usage    : my $error = $geo->error();
 Function : Fetch error messages produced by the Google Maps XML server.
            Errors can be produced for a number of reasons, e.g. inability
            of the server to resolve a street address to geographical
            coordinates.
 Returns  : The most recent error string.  Calling this method clears the
            last error.
 Args     : n/a

=cut

sub error {
  my ( $self, $msg ) = @_;
  if ( !defined($msg) or ! $self->isa(__PACKAGE__) ) {
    my $error = $self->{error};
    $self->{error} = undef;
    return $error;
  }
  else {
    $self->{error} = $msg;
  }
}

=head2 location()

 Usage    : my $loc = $geo->location( address => $address );
 Function : creates a new Geo::Google::Location object, given a
            street address.
 Returns  : a Geo::Google::Location object, or undef on error
 Args     : an anonymous hash:
            key       required?   value
            -------   ---------   -----
            address   yes         address to search for
            id        no          unique identifier for the
                                  location.  useful if producing
                                  XML.
            icon      no          image to be used to represent
                                  point in Google Maps web
                                  application
            infoStyle no          unknown.  css-related, perhaps?

=cut

sub location {
  my ( $self, %arg ) = @_;

  my $address   = $arg{'address'} or ($self->error("must provide an address to location()") and return undef);

  my $page = get( sprintf( LQ, uri_escape($address) ) );
  $page =~ m!(<page.+/page>)!;
  my $parser = XML::DOM::Parser->new();
  my $dom = $parser->parse( $1 );

  # error of some sort
  if ( my ( $node ) = $dom->findnodes('//error') ) {
    my $error = $node->toString();
    #pretty-print error
    $error =~ s!</?b>!'!gs;
    $error =~ s!</p>!\n!gs;
    $error =~ s!</li>!\n!gs;
    $error =~ s!<li>!  -!gs;
    $error =~ s!<.+?>!!gs;
    $error = _html_unescape($error);
    $self->error( $error );
    return undef;
  }
  # ambiguous input
  elsif ( my @nodes = $dom->findnodes('//refinements//i') ) {
    $self->error( "Your query for '$address' must be refined, it returned ".
         scalar(@nodes).":\n".
         join("\n", map { "  -"._html_unescape($_->getFirstChild->toString()) } @nodes)
    );
    return undef;
  }

  my @result = ();
  if ( my ( @nodes ) = $dom->findnodes('//location') ) {
    my $i = 0;
    foreach my $node ( @nodes ) {
#warn $node;
      my $loc = $self->_xml2location($node,%arg);
      push @result, $loc;
    }

    return @result;
  }
}

=head2 near()

 Usage    : my @near = $geo->near( $loc, $phrase );
 Function : searches Google Local for records matching the
            phrase provided, with the constraint that they are
            physically nearby the Geo::Google::Location object
            provided.  search phrase is passed verbatim to Google.
 Returns  : a list of Geo::Google::Location objects
 Args     : 1. A Geo::Google::Location object
            2. A search phrase.

=cut

sub near {
  my ( $self, $where, $query ) = @_;
  my $page = get( sprintf( NQ, join(',', $where->lines ), $query ) );
  $page =~ m!(<page.+/page>)!;
  my $parser = XML::DOM::Parser->new();
  my $dom = $parser->parse( $1 );

  my @result = ();
  if ( my ( @nodes ) = $dom->findnodes('//location') ) {
    my $i = 0;
    foreach my $node ( @nodes ) {
      $i++;
      my $loc = $self->_xml2location($node);
      push @result, $loc;
    }

    return @result;
  }
}

=head2 path()

 Usage    : my $path = $geo->path( $from, $to );
 Function : get driving directions between two points
 Returns  : a Geo::Google::Path object
 Args     : 1. a Geo::Google::Location object (from)
            2. a Geo::Google::Location object (to)

=cut

sub path {
  my ( $self, $s, $d ) = @_;

  if( !defined($s) or !defined($d) ) {
    $self->error("either source ('$s') or destination ('$d') is not defined");
    return undef;
  }
  elsif( (!$s->isa('Geo::Google::Location')) or (!$d->isa('Geo::Google::Location')) ) {
    $self->error("either source ('$s') or destination ('$d') is not a Geo::Google::Location object, or subclass thereof");
    return undef;
  }
  else {
    my $s_address = join(', ',$s->lines);
    my $d_address = join(', ',$d->lines);

    my $parser = XML::DOM::Parser->new();

    my $page = get( sprintf( LQ, uri_escape("$s_address to $d_address") ) );
    $page =~ m!(<page.+/page>)!;

    my $dom = $parser->parse( $1 );

    my $enc_points = $dom->findnodes('//polyline/points');
    my $total = $dom->findnodes('//segments')->get_node(1);

    my @nodes = ( $s );
    my @segs = $dom->findnodes('//segment');

    my @points = _decode($enc_points);


#warn scalar(@segs);
#warn scalar(@points);
#warn $enc_points;

#warn join "\n", map {$_->toString} @segs;

    my $last_point = undef;
    my $last_seg = undef;
    my @segments = ();
    my @points_subset = ();
    my $m = 0;
    while ( @points ) {
      my $lat = shift @points;
      my $lon = shift @points;
      $m++;

      if ( ! $last_point ) {
        $last_point = Geo::Google::Location->new(
          latitude  => $lat,
          longitude => $lon,
        );
        push @points_subset, $last_point;

        if ( $m-1 == $segs[0]->getAttribute('pointIndex') ) {
#warn "new segment at: ".($m-1);
          my $seg = shift @segs;
          push @segments, Geo::Google::Segment->new(
            points     => \@points_subset,
            from       => $last_point,
            to         => $last_point,
            distance   => $seg->getAttribute('distance'),
            meters     => $seg->getAttribute('meters'),
            seconds    => $seg->getAttribute('seconds'),
            time       => $seg->getAttribute('time'),
            pointIndex => $seg->getAttribute('pointIndex'),
            id         => $seg->getAttribute('id'),
            text       => join '', map { _html_unescape($_->toString) } $seg->getChildNodes,
          );
          @points_subset = ();
        }
        next;
      }

      my $point = Geo::Google::Location->new(
        latitude  => $lat,
        longitude => $lon,
      );
      push @points_subset, $point;

      my $seg = undef;
      if ( $segs[0] ) {
        next unless $m-1 == $segs[0]->getAttribute('pointIndex');
        $seg = shift @segs;

        push @segments, Geo::Google::Segment->new(
          points     => [@points_subset],
          from       => $last_point,
          to         => $point,
          distance   => $seg->getAttribute('distance'),
          meters     => $seg->getAttribute('meters'),
          seconds    => $seg->getAttribute('seconds'),
          time       => $seg->getAttribute('time'),
          pointIndex => $seg->getAttribute('pointIndex'),
          id         => $seg->getAttribute('id'),
          text       => join '', map { _html_unescape($_->toString) } $seg->getChildNodes,
        );
      } else {
        push @{ $segments[0]->{points} }, $point;
      }

      $last_point = $point;
      $last_seg = $seg;
      @points_subset = ();
    }

    my $path = Geo::Google::Path->new(
      segments  => \@segments,
      meters    => $total->getAttribute('meters'),
      seconds   => $total->getAttribute('seconds'),
      distance  => $total->getAttribute('distance'),
      time      => $total->getAttribute('time'),
      polyline  => $enc_points,
    );

    return $path;

#$Data::Dumper::Maxdepth=6;
#warn Dumper($path);
 
#<segments distance="0.6&#160;mi" meters="865" seconds="56" time="56 secs">
#  <segment distance="0.4&#160;mi" id="seg0" meters="593" pointIndex="0" seconds="38" time="38 secs">Head <b>southwest</b> from <b>Venice Blvd</b></segment>
#  <segment distance="0.2&#160;mi" id="seg1" meters="272" pointIndex="6" seconds="18" time="18 secs">Make a <b>U-turn</b> at <b>Venice Blvd</b></segment>
#</segments>
    push @nodes, $d;
    return @nodes;
  }
}

=head1 INTERNAL FUNCTIONS AND METHODS

=cut

=head2 _decode()

 Usage    : my @points = _decode($encoded_points);
 Function : decode a polyline into its composite lat/lon pairs
 Returns  : an array
 Args     : a string

=cut

sub _decode {
  my $points = shift;
  return undef unless defined $points;
  my @points = split '', $points;
  my $Ch = scalar(@points);
  my $pb = 0;
  my @locations = ();
  my $Ka = 0;
  my $Pa = 0;
  my $i = undef;
  while ( $pb < $Ch ) {
    my $oc = 0;
    my $Fa = 0;

    while ( 1 ) {
      my $ub = ord($points[$pb]) - 63;
      $pb++;
      $Fa |= ($ub & 31) << $oc;
      $oc += 5;
      last if $ub < 32;
    }

    if ( $Fa & 1 ) {
      $i = ~($Fa >> 1);
    } else {
      $i = $Fa >> 1;
    }

    $Ka += $i;
    push @locations, ($Ka * 1E-5);

    #negative values come out wrong -- some bitshift error, will fix later.
    #it's a hack, but it works.
    while ( $locations[-1] >= 42000 ) {
      $locations[-1] -= 42949.67296;
    }

    $oc = 0;
    $Fa = 0;

    while ( 1 ) {
      my $ub = ord($points[$pb]) - 63;
      $pb++;
      $Fa |= ($ub & 31) << $oc;
      $oc += 5;
      last if $ub < 32;
    }
    if ( $Fa & 1 ) {
      $i = ~($Fa >> 1);
    } else {
      $i = $Fa >> 1;
    }

    $Pa += $i;
    push @locations, ($Pa * 1E-5);

    #negative values come out wrong -- some bitshift error, will fix later.
    #it's a hack, but it works.
    while ( $locations[-1] >= 42000 ) {
      $locations[-1] -= 42949.67296;
    }

  }

  #prettify results
  return map {sprintf("%3.5f",$_)} @locations;
}

=head2 _encode()

 Usage    : my $encoded_points = _encode(@points);
 Function : encode lat/lon pairs into a polyline string
 Returns  : a string
 Args     : an array

=cut

sub _encode {
  my @points = @_;
  my $numPoints = scalar(@points);

  @points = map { int($_/0.00001) } @points;
  my @l = ();
  my $xo = 0;
  my $yo = 0;

  foreach my $i ( 0..$numPoints-1 ) { 
    my $y = $points[ $i << 1 ];
    my $yd = $y - $yo;
    $yo = $y;

    my $f = ( abs($yd) << 1 ) - ( $yd < 0 );

    while ( 1 ) {
      my $e = $f & 31;
      $f >>= 5;
      if ( $f ) {
        $e |= 32;
      }
      push @l, chr($e+63);
      last if $f == 0;
    }

    my $x = $points[ ($i << 1) + 1 ];
    my $xd = $x - $xo;
    $xo = $x;
    $f = ( abs($xd) << 1 ) - ( $xd < 0 );
    while ( 1 ) {
      my $e = $f & 31;
      $f >>= 5;
      if ( $f ) { 
        $e |= 32;
      }
      push @l, chr($e+63);
      last if $f == 0;
    }
  }
  return join '', @l;
}

=head2 _html_unescape()

 Usage    : my $clean = _html_unescape($dirty);
 Function : does HTML unescape of & > < " special characters
 Returns  : an unescaped HTML string
 Args     : an HTML string.

=cut

sub _html_unescape {
  my ( $raw ) = shift;

  while ( $raw =~ m!&(amp|gt|lt|quot);!) {
    $raw =~ s!&amp;!&!g;
    $raw =~ s!&gt;!>!g;
    $raw =~ s!&lt;!<!g;
    $raw =~ s!&quot;!"!g;
  }
  return $raw;
}

=head2 _xml2location()

 Usage    : my $loc = _xml2location($xml);
 Function : converts a Google Maps XML document to a Geo::Google::Location object
 Returns  : a Geo::Google::Location object
 Args     : a Google Maps XML document.

=cut

sub _xml2location {
  my ( $self, $node, %arg ) = @_;

  my $lat = $node->findnodes('point')->get_node(1)->getAttribute('lat');
  my $lng = $node->findnodes('point')->get_node(1)->getAttribute('lng');
  my @lines = map { _html_unescape($_->getFirstChild->toString()) } ( $node->findnodes('info/address//line') );
#FIXME

  my $title;
  #differs if performing a "near" search.
  if ( $node->findnodes('info/title') ) {
#warn "has title";
    ( $title ) = $node->findnodes('info/title')->get_node(1)->toString =~ m!.+?>(.+)<!; #yeah, i know.
  }
  else {
    ( $title ) = $node->findnodes('info')->get_node(1)->toString =~ m!.+?>(.+)<!; #yeah, i know.
  }


#unshift @lines, $title;

  my $loc = Geo::Google::Location->new(
    title     => _html_unescape($title),
    latitude  => $lat,
    longitude => $lng,
    lines     => [@lines],
    id        => $node->getAttribute('id')
                 || $arg{'id'}
                 || md5_hex( localtime() ),
    infostyle => $node->getAttribute('infoStyle')
                 || $arg{'icon'}
                 || 'http://maps.google.com/mapfiles/marker.png',
    icon      => $node->findnodes('icon')->get_node(1)->getAttribute('image')
                 || $arg{'infoStyle'}
                 || 'http://maps.google.com/maps?file=gi&amp;hl=en',
  );
  return $loc;

qq(
    <location id="H" infoStyle="/maps?file=li&amp;hl=en">
      <point lat="34.036003" lng="-118.477652"/>
      <icon class="local" image="/mapfiles/markerH.png"/>
      <info>
        <title xml:space="preserve"><b>Starbucks</b> Coffee: Santa Monica</title>
        <address>
          <line>2525 Wilshire Blvd</line>
          <line>Santa Monica, CA 90403</line>
        </address>
        <phone>(310) 264-0669</phone>
        <distance>1.2 mi SW</distance>
        <references count="5">
          <reference>
            <url>http://www.hellosantamonica.com/YP/c_COFFEESTORES.Cfm</url>
            <domain>hellosantamonica.com</domain>
            <title xml:space="preserve">Santa Monica California Yellow Pages. COFFEE STORES <b>...</b></title><shorttitle xml:space="preserve">Santa Monica California Yel...</shorttitle>
          </reference>
        </references>
        <url>/local?q=Starbucks+Coffee:+Santa+Monica&amp;near=Santa+Monica,+CA+90403&amp;latlng=34047451,-118462143,1897416402105863377</url>
      </info>
    </location>
);
}

1;

#http://brevity.org/toys/google/google-draw-pl.txt

__END__
