=head1 NAME

Geo::Google - Perform geographical queries using Google Maps

=head1 SYNOPSIS

  use strict;
  use Data::Dumper;
  use Geo::Google;

  #Allen's office
  my $gonda_addr = '695 Charles E Young Dr S, Westwood, CA 90024';
  #Stan's Donuts
  my $stans_addr = '10948 Weyburn Ave, Westwood, CA 90024';
  #Roscoe's House of Chicken and Waffles
  my $roscoes_addr = "5006 W Pico Blvd, Los Angeles, CA";

  #Instantiate a new Geo::Google object.
  my $geo = Geo::Google->new();

  #Create Geo::Google::Location objects.  These contain
  #latitude/longitude coordinates, along with a few other details
  #about the locus.
  my ( $gonda ) = $geo->location( address => $gonda_addr );
  my ( $stans ) = $geo->location( address => $stans_addr );
  my ( $roscoes ) = $geo->location( address => $roscoes_addr );
  print $gonda->latitude, " / ", $gonda->longitude, "\n";
  print $stans->latitude, " / ", $stans->longitude, "\n";
  print $roscoes->latitude, " / ", $roscoes->longitude, "\n";

  #Create a Geo::Google::Path object from $gonda to $roscoes
  #by way of $stans.
  my ( $donut_path ) = $geo->path($gonda, $stans, $roscoes);

  #A path contains a series of Geo::Google::Segment objects with
  #text labels representing turn-by-turn driving directions between
  #two or more locations.
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

  # Export a location as XML for part of a Google Earth KML file
  my $strStansDonutsXML = $stans->toXML();
 
  # Export a location as JSON data to use with Google Maps
  my $strRoscoesJSON = $roscoes->toJSON();

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

Allen Day E<lt>allenday@ucla.eduE<gt>, Michael Trowbridge 
E<lt>michael.a.trowbridge@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2004-2007 Allen Day.  All rights
reserved. This program is free software; you can redistribute it 
and/or modify it under the same terms as Perl itself.

=head1 BUGS / TODO

Report documentation and software bugs to the author, or better yet,
send a patch.  Known bugs/issues:

=over

=item Polyline decoding needs to be cleaned up. 

=item Lack of documentation.

JSON exporting is not exactly identical to the original Google 
JSON response.  Some of the Google Maps-specific data is discarded 
during parsing, and the perl JSON module does not allow for bare keys 
while exporting to a JSON string.  It should still be functionally 
interchangeable with a Google JSON reponse.

=back

=head1 SEE ALSO

  http://maps.google.com
  http://www.google.com/apis/maps/
  http://libgmail.sourceforge.net/googlemaps.html

=cut

package Geo::Google;
use strict;
our $VERSION = '0.03';

#this gets a javascript page containing map XML
use constant LQ => 'http://maps.google.com/maps?output=js&v=1&q=%s';

#this gets a javascript page containing map XML.  special for "nearby" searches
use constant NQ => 'http://maps.google.com/maps?output=js&v=1&near=%s&q=%s';

#used in polyline codec
use constant END_OF_STREAM => 9999;

#external libs
use Data::Dumper;
use Digest::MD5 qw( md5_hex );
use HTML::Entities;
use JSON;
use LWP::Simple;
use URI::Escape;

#our libs
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

  my $json = new JSON (skipinvalid => 1, barekey => 1, 
			quotapos => 1, unmapping => 1 );
  my $response_json = undef;
  my $page = get( sprintf( LQ, uri_escape($address) ) );

  # See if google returned no results
  if ( $page =~ /did\snot\smatch\sany\slocations/i ) {
    $self->error( "Google couldn't match any locations matching "
	. "$address.");
    return undef;
  }
  # attept to locate the JSON formatted data block
  elsif ($page =~ 	
	/loadVPage\((.+),document\.getElementById\(/is) {
	my $strJSON = $1;
	$response_json = $json->jsonToObj($strJSON);
	}
  else {
	$self->error( "Unable to locate the JSON format data in " 
		. "google's response.");
	return undef;
	}

  if ( scalar(@{$response_json->{"overlays"}->{"markers"}}) > 0 ) {
	my @result = ();
	foreach my $marker (@{$response_json->{"overlays"}->{"markers"}}) {
		my $loc = $self->_obj2location($marker, %arg);
		push @result, $loc;
	}		
  	return @result;
  }
  else {
	$self->error("Found the JSON Data block and was "
		. "able to parse it, but it had no location markers "
		. "in it.  Maybe Google changed their "
		. "JSON data structure?.");
	return undef;
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
  
  my $json = new JSON (skipinvalid => 1, barekey => 1, 
			quotapos => 1, unmapping => 1 );
  my $response_json = undef;

  # See if google returned no results
  if ( $page =~ /did\snot\smatch\sany\slocations/i ) {
    $self->error( "Google couldn't find a $query near " . $where->title);
    return undef;
  }
  # attept to locate the JSON formatted data block
  elsif ($page =~ 	
	/loadVPage\((.+),document\.getElementById\(/is) {
	my $strJSON = $1;
	$response_json = $json->jsonToObj($strJSON);
	}
  else {
	$self->error( "Unable to locate the JSON format data in " 
		. "google's response.");
	return undef;
	}

  if ( scalar(@{$response_json->{"overlays"}->{"markers"}}) > 0 ) {
	my @result = ();
	foreach my $marker (@{$response_json->{"overlays"}->{"markers"}}) {
		my $loc = $self->_obj2location($marker);
		push @result, $loc;
	}		
  	return @result;
  }
  else {
	$self->error("Found the JSON Data block and was "
		. "able to parse it, but it had no location markers"
		. "in it.  Maybe Google changed their "
		. "JSON data structure?");
	return undef;
  }
}

=head2 path()

 Usage    : my $path = $geo->path( $from, $OptionalWaypoints, $to );
 Function : get driving directions between two points
 Returns  : a Geo::Google::Path object
 Args     : 1. a Geo::Google::Location object (from)
	    2. optional Geo::Google::Location waypoints
            3. a Geo::Google::Location object (final destination)

=cut

sub path {
  my ( $self, @locations ) = @_;
  my $json = new JSON (skipinvalid => 1, barekey => 1, 
			quotapos => 1, unmapping => 1 );
  my $response_json = undef;

  if(scalar(@locations) < 2) {
    $self->error("Less than two locations were passed to the path function");
    return undef;
  }
  #check each @locations element to see if it is a Geo::Google::Location
  for (my $i=0; $i<=$#locations; $i++) {
	if(!$locations[$i]->isa('Geo::Google::Location')) {
	    $self->error("Location " . ($i+1)
			. " passed to the path function is not a "
			. "Geo::Google::Location"
			. " object, or subclass thereof");
	    return undef;
	}
  }

  # construct the google search text
  my $googlesearch = "from: " . join(', ', $locations[0]->lines);
  for (my $i=1; $i<=$#locations; $i++){
	$googlesearch .= " to:" . join(', ', $locations[$i]->lines);
  }

  my $page = get( sprintf( LQ, uri_escape( $googlesearch ) ) );

  # See if google returned no results
  if ( $page =~ /did\snot\smatch\sany\slocations/i ) {
    $self->error( "Google couldn't find one of the locations"
		. " you provided for your directions query");
    return undef;
  }
  # attept to locate the JSON formatted data block
  elsif ($page =~ 	
	/loadVPage\((.+),document\.getElementById\(/is) {
	my $strJSON = $1;

	# Extract the JSON data structure from the response.
	$response_json = $json->jsonToObj($strJSON);
	}
  else {
	$self->error( "Unable to locate the JSON format data in " 
		. "google's response.");
	return undef;
  }

  my $enc_points = $response_json->{"overlays"}->{"polylines"}->[0]->{"points"};
  my @points = _decode($enc_points);

  # extract a series of directions from HTML inside the panel 
  # portion of the JSON data response, stuffing them in @html_segs
  my @html_segs;
  my $stepsfound = 0;

  my $panel = $response_json->{'panel'};
  $panel =~ s/&#160;/ /g;

  my @subpaths = $panel =~ m#(<table class=042(ddrsteps pw|ddwpt_table)042.+?</table>\s*</div>)#gs; #ddspt_table
  #my ( $subpanel ) = $response_json->{'panel'} =~ m#<table class=042ddrsteps pw042>(.+)</table>#s;

  foreach my $subpath ( @subpaths ) {
    my @segments = split m#</tr>\s*<tr#s, $subpath;
    foreach my $segment ( @segments ) {
      #skip irrelevant waypoint rows
      if ( $subpath =~ m#ddwpt_table#s && $segment !~ m#ddptlnk#s ) { next }

      my ( $id )         = $segment =~ m#id=042(.+?)042#s;
      my ( $pointIndex ) = $segment =~ m#polypoint=042(.+?)042#s;
      my ( $html )       = $segment =~ m#042dirsegtext042>(.+?)</td>#s;
      my ( $distance )   = $segment =~ m#042sdist042>.*?<b>(.+?)</b>.*?</td>#s;
      my ( $time )       = $segment =~ m#042segtime pw042>(.+?)<#s;

      if ( ! defined( $id ) ) {
        if ( $subpath =~ m#waypoint=042(.+?)042#s ) {
          $id = "waypoint_$1";
        }
      }

      next unless $id;

      if ( ! $html ) {
        #destinations/waypoints are different
        ( $html ) = $segment =~ m#042milestone042.+?>(.+?)<td class=042closer#s;
      }

      if ( ! $time ) {
        #some segments are different (why? what is the pattern?)
        my ( $d2, $t2 ) = $segment =~ m#timedist ul.+?>(.+?)\(about&\#160;(.+?)\)</td>#s;
        $time = $t2;
        $distance ||= $d2;
      }

      #some segments have no associated point, e.g. when there are long-distance driving segments

      #some segments have time xor distance (not both)
      $distance   ||= ''; $distance = decode_entities( $distance ); $distance =~ s/\s+/ /g;
      $time       ||= ''; $time     = decode_entities( $time     ); $time =~ s/\s+/ /g;

#print
#"$id
#	$pointIndex
#	$distance
#	$time
#	$html
#
#";
#warn

      push (@html_segs, {
        distance   => $distance,
        time       => $time,
        pointIndex => $pointIndex,
        id         => $id,
        html       => $html
      });
      $stepsfound++;
    }
  }
#die;

  if ($stepsfound == 0) {
	$self->error("Found the HTML directions from the JSON "
			. "reponse, but was not able to extract "
			. "the driving directions from the HTML");
	return undef;
  }
  my @segments = ();
  # The first point in the first segment should be the start point, 
  # but google doesn't include that in their polyline, so I compensate
  my @points_subset = ( $locations[0] );
  my $m = -1;
  #  Correlate the array of lats and longs we decoded from the 
  # JSON object with the segments we extracted from the panel 
  # HTML and put the result into an array of
  # Geo::Google::Location objects 
  while ( @points ) {
      my $lat = shift @points;
      my $lon = shift @points;
      $m++;

      my %html_seg;

      my $point = Geo::Google::Location->new(
          latitude  => $lat,
          longitude => $lon,
        );

      push @points_subset, $point;

      if ( $html_segs[1] ) { 
	# There's a segment after the one we're working on
	# This tests to see if we need to wrap up the current segment
        if ( defined( $html_segs[1]{'pointIndex'} ) ) {
          next unless $m + 1 == $html_segs[1]{'pointIndex'};
        }

        %html_seg = %{shift @html_segs};

        push @segments, Geo::Google::Segment->new(
          pointIndex => $html_seg{'pointIndex'},
          id         => $html_seg{'id'},
          html       => decode_entities($html_seg{"html"}),
          distance   => $html_seg{'distance'},
          time       => $html_seg{'time'},
          from       => $points_subset[0],
          to         => $point,
          points     => [@points_subset]
        );
        @points_subset = ();
      } elsif ($html_segs[0]) { # We're working on the last segment
	# This tests to see if we need to wrap up the last segment
         next unless (! $points[0]);
         %html_seg = %{shift @html_segs};
         push @segments, Geo::Google::Segment->new(
            pointIndex => $html_seg{'pointIndex'},
            id         => $html_seg{'id'},
            html       => decode_entities($html_seg{"html"}),
            distance   => $html_seg{'distance'},
            time       => $html_seg{'time'},
            from       => $points_subset[0],
            to         => $locations[$#locations],
            points     => [@points_subset]
          );
          @points_subset = ();
      } else { # we accidentally closed out the last segment early
          push @{ $segments[$#segments]->{points} }, $point;
      }
  }
  # The last point in the last segment should be the final 
  # destination, but google doesn't put that in the polyline.
  push @{ $segments[$#segments]->{points} }, $locations[$#locations];
    

  # Extract the total information using a regex on the panel hash
  # At the end of the "printheader", we're looking for:
  # 282&#160;mi&#160;(about&#160;4 hours 27 mins)</td></tr></table>
  if ($response_json->{"printheader"} =~
		/(\d+\.?\d*)\&\#160;(mi|km|m)\&\#160;\(about\&\#160;(.+?)\)<\/td><\/tr><\/table>$/s){
	my $path = Geo::Google::Path->new(
	   segments  => \@segments,
	   distance  => $1 . " " . $2,
	   time      => $3,
	   polyline  => $enc_points,
	   locations => [ @locations ],
	   panel     => $response_json->{"panel"},
	   levels    => $response_json->{"overlays"}->{"polylines"}->[0]->{"levels"}
					);

	return $path;
  } else {
	$self->error("Could not extract the total route distance "
			. "and time from google's directions");
	return undef;
  }

#$Data::Dumper::Maxdepth=6;
#warn Dumper($path);
 
#<segments distance="0.6&#160;mi" meters="865" seconds="56" time="56 secs">
#  <segment distance="0.4&#160;mi" id="seg0" meters="593" pointIndex="0" seconds="38" time="38 secs">Head <b>southwest</b> from <b>Venice Blvd</b></segment>
#  <segment distance="0.2&#160;mi" id="seg1" meters="272" pointIndex="6" seconds="18" time="18 secs">Make a <b>U-turn</b> at <b>Venice Blvd</b></segment>
#</segments>
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

=head2 _obj2location()

 Usage    : my $loc = _obj2location($obj);
 Function : converts a perl object generated from a Google Maps 
		JSON response to a Geo::Google::Location object
 Returns  : a Geo::Google::Location object
 Args     : a member of the $obj->{overlays}->{markers}->[] 
		anonymous array that you get when you read google's 
		JSON response and parse it using JSON::jsonToObj()

=cut

sub _obj2location {
  my ( $self, $marker, %arg ) = @_;

  my @lines;
  my $title;
  my $description;
  # Check to make sure that the info window contents are HTML
  # and that google hasn't changed the format since I wrote this
  if ( $marker->{"infoWindow"}->{"type"} eq "html" ) {
	if ($marker->{"laddr"} =~ 
		/\((.+)\)\s\@\-?\d+\.\d+,\-?\d+\.\d+$/s){
		$title = $1;
	}
	else {
		$title = $marker->{"laddr"};
	}

	$description = decode_entities($marker->{"infoWindow"}->{"basics"});
	# replace </P>, <BR>, <BR/> and <BR /> with newlines
	$description =~ s/<\/p>|<br\s?\/?>/\n/gi;
	# remove all remaining markup tags
	$description =~ s/<.+>//g;
  }
  else {
	# this is a non-fatal nuisance error, only lat/long are 
	# absolutely essential products of this function
    $title = "Could not extract a title or description from "
	. "google's response.  Have they changed their format since "
	. "this function was written?";
  }  

  my $loc = Geo::Google::Location->new(
    title     => $title,
    latitude  => $marker->{"lat"},
    longitude => $marker->{"lng"},
    lines     => [split(/\n/, $description)],
    id        => $marker->{"id"}
                 || $arg{'id'}
                 || md5_hex( localtime() ),
    infostyle => $arg{'icon'}
                 || 'http://maps.google.com/mapfiles/marker.png',
    icon      => "http://maps.google.com" . $marker->{"image"}
                 || $arg{'infoStyle'}
                 || 'http://maps.google.com/mapfiles/arrow.png'
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

=head2 _JSONrenderSkeleton()

 Usage    : my $perlvariable = _JSONrenderSkeleton();
 Function : creates the skeleton of a perl data structure used by 
		the Geo::Google::Location and Geo::Google::Path for 
		rendering to Google Maps JSON format
 Returns  : a mildly complex multi-level anonymous hash/array 
		perl data structure that corresponds to the Google 
		Maps JSON data structure
 Args     : none

=cut

sub _JSONrenderSkeleton{
	# This data structure is based on a sample query
	# performed on 27 Dec 06 by Michael Trowbridge
	return {
          'urlViewport' => 0,
          'ei' => '',
          'form' => {
                      'l' => {
                               'q' => '',
                               'near' => ''
                             },
                      'q' => {
                               'q' => ''
                             },
                      'd' => {
                               'saddr' => '',
                               'daddr' => '',
                               'dfaddr' => ''
                             },
                      'selected' => ''
                    },
          'overlays' => {
                          'polylines' => [],
                          'markers' => [],
                          'polygons' => []
                        },
          'printheader' => '',
          'modules' => [
                         undef
                       ],
          'viewport' => {
                          'mapType' => '',
                          'span' => {
                                      'lat' => '',
                                      'lng' => ''
                                    },
                          'center' => {
                                        'lat' => '',
                                        'lng' => ''
                                      }
                        },
          'panelResizeState' => 'not resizeable',
          'ssMap' => {
                       '' => ''
                     },
          'vartitle' => '',
          'url' => '/maps?v=1&q=URI_ESCAPED_QUERY_GOES_HERE&ie=UTF8',
          'title' => ''
        };
}

1;

#http://brevity.org/toys/google/google-draw-pl.txt

__END__
