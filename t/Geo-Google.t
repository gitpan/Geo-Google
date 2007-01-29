#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 44;
BEGIN {
  use_ok('Geo::Google');
  use_ok('LWP::Simple');
};

########################

use strict;
use Data::Dumper;
use Geo::Google;

ok( my $geo  = Geo::Google->new()                            , "Instantiated a new Geo::Google object" );
is( ref( $geo ), 'Geo::Google'                               , "Object type okay" );
is( $geo->version(), '0.03'                                  , "Check Geo::Google version number" );

ok( my $add1 = '695 Charles E Young Dr S, Westwood, CA 90024', "Dept. of Human Genetics, UCLA" );
ok( my $add2 = '10948 Weyburn Ave, Westwood, CA 90024'       , "Stan's Donuts"  );
ok( my $add3 = '5006 W Pico Blvd, Los Angeles, CA'           , "Roscoe's House of Chicken and Waffles" );

#Create Geo::Google::Location objects.  These contain latitude/longitude coordinates,
#along with a few other details about the locus.
ok( my ($loc1) = $geo->location( address => $add1 )          , "loc1 on the map"     );
isnt( $loc1, undef                                           , "...and defined"      );
is( $loc1->latitude(), "34.067107"                           , "...latitude okay"    );
is( $loc1->longitude(), "-118.444578"                        , "...longitude okay"   );
ok( my ($loc2) = $geo->location( address => $add2 )          , "loc2 on the map"     );
isnt( $loc2, undef                                           , "...and defined"      );
is( $loc2->latitude(), "34.062357"                           , "...latitude okay"    );
is( $loc2->longitude(), "-118.447113"                        , "...longitude okay"   );
ok( my ($loc3) = $geo->location( address => $add3 )          , "loc3 on the map"     );
isnt( $loc3, undef                                           , "...and defined"      );
is( $loc3->latitude(), "34.047608"                           , "...latitude okay"    );
is( $loc3->longitude(), "-118.346247"                        , "...longitude okay"   );

#Create a Geo::Google::Path object from $loc1 to $loc3 via waypoint $loc2
#A path contains a series of Geo::Google::Segment objects with text labels representing
#turn-by-turn driving directions between two or more locations.
ok( my ( $path ) = $geo->path( $loc1, $loc2, $loc3 )         , "Instantiated a new Geo::Google::Path" );
isnt($path, undef                                            , "directions from gonda to stans to roscoes and make a path object from the JSON response");
ok( my @segments = $path->segments()                         , "Path contains segments" );
is( scalar( @segments ), 17                                  , "Correct number of segments on the path" );

#Test directions
my $segment = undef;

ok( $segment = $segments[1] );
is ( $segment->id(), 'dirsegment_2'                          , 'segment id okay'       );
is ( $segment->pointIndex(), '2'                             , 'segment id okay'       );
is ( $segment->distance(), '0.2 mi'                          , 'segment distance okay' );
is ( $segment->text(), 'Turn left at Westwood Plaza'         , 'segment text okay'     );

ok( $segment = $segments[6] );
is ( $segment->id(), 'dirsegment_15'                         , 'segment id okay'       );
is ( $segment->pointIndex(), '15'                            , 'segment id okay'       );
is ( $segment->distance(), '0.3 mi'                          , 'segment distance okay' );
is ( $segment->text(), 'Turn left at Gayley Ave'             , 'segment text okay'     );

#foreach my $s ( @segments ) {
#  print "*".$s->id()."\n";
#  print "\t".$s->text()."\n";
#  print "\t".$s->distance()."\n";
#  print "\t".$s->time()."\n";
##  print "\t".$s->pointIndex()."\n";
#}

#Geo::Google::Segment objects contain a series of Geo::Google::Location objects --
#one for each time the segment deviates from a straight line to the end of the segment.
my @points = $segments[1]->points;

is( scalar( @points ), 5                                     , 'Correct number of points in segment' );
is( $points[3]->latitude(), '34.06547'                       , 'Point latitude okay' );
is( $points[3]->longitude(), '-118.44544'                    , 'Point longitude okay' );

#Find coffee near to Stan's Donuts
ok( my @near = $geo->near( $loc2, 'coffee' )                 , "Search for coffee near Stan's Donuts" );
is( ref( $near[0] ), 'Geo::Google::Location',                , "Search returns Geo::Google::Location objects" );

#Too many.  How about some Coffee Bean & Tea Leaf?
ok( (@near = grep { $_->title =~ /Coffee.*?Bean/i } @near)   , "Filter coffee shops to Coffee Bean" );

#Still too many!  Let's find the closest with a little trig and a Schwartzian transform
my ( $coffee ) = map { $_->[1] }
                 sort { $a->[0] <=> $b->[0] }
                  map { [ sqrt(
                    ($_->longitude - $loc2->longitude)**2
                      +
                    ($_->latitude - $loc2->latitude)**2
                  ), $_ ] } @near;

is( $coffee->latitude(), '34.061894'                         , 'Coffee latitude okay');
is( $coffee->longitude(), '-118.447887'                      , 'Coffee latitude okay');

# Exports
ok( my $loc2XML = $loc2->toXML()                             , "Stan's Donuts as Google Earth KML (XML) format" );
ok( my $loc3XML = $loc3->toJSON()                            , "Roscoe's as Google Maps JSON format" );

