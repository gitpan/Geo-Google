package Geo::Google::Path;
use strict;
use warnings;
use Data::Dumper;
use URI::Escape;
our $VERSION = '0.01';

use constant FMT => <<_FMT_;
<segments distance="%s" meters="%s" seconds="%s" time="%s">
%s</segments>
_FMT_

#<segments distance="0.6&#160;mi" meters="865" seconds="56" time="56 secs">
#  <segment distance="0.4&#160;mi" id="seg0" meters="593" pointIndex="0" seconds="38" time="38 secs">Head <b>southwest</b> from <b>Venice Blvd</b></segment>
#  <segment distance="0.2&#160;mi" id="seg1" meters="272" pointIndex="6" seconds="18" time="18 secs">Make a <b>U-turn</b> at <b>Venice Blvd</b></segment>
#</segments>

sub new {
  my $class = shift;
  my %arg = @_;
  my $self = bless \%arg, $class;
}

sub distance { return shift->{'distance'} }
sub meters   { return shift->{'meters'} }
sub polyline { return shift->{'polyline'} }
sub seconds  { return shift->{'seconds'} }
sub segments { my $self = shift; return $self->{'segments'} ? @{ $self->{'segments'} } : () }
sub time     { return shift->{'time'} }

sub toString {
  my $self = shift;
  my $content = join "", map { $_->toString } @{ $self->segments };
  return sprintf( FMT,
    $self->distance(),
    $self->meters(),
    $self->seconds(),
    $self->time(),
    $content,
  );
}

1;
__END__
 Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Geo::Google::Path - A path, by automobile, between two loci.

=head1 SYNOPSIS

  use Geo::Google::Path;
  # you shouldn't need to construct these yourself,
  # have a Geo::Google object do it for you.

=head1 DESCRIPTION

Google Maps is able to serve up directions between two points.  Directions
consist of two types of components:

  1. a series of points along a "polyline".
  2. a series of annotations, each of which applies to a contiguous
  range of points.

In the Geo::Google object model, directions are available by calling path()
on a Geo::Google instance.  The return value is a Geo::Google::Path object,
which is a composite of Geo::Google::Segment objects, which are in turn
composites of Geo::Google::Location objects.

=head1 OBJECT METHODS

Geo::Google::Path objects provide the following accessor methods

 Method      Description
 ------      -----------
 distance    length of the segment, in variable, human friendly units.
 meters      length of the segment, in meters.
 polyline    a string encoding the points in the path.
 seconds     a time estimate, in seconds, for how long the path will
             take to travel by automobile.
 segments    a list of Geo::Google::Segment segments along the path.
             a segment has 0..1 driving directions associated with it.
 time        a time estimate, in variable, human-friendly units for how long
             the segment will take to travel by automobile.
 toString    a method that renders the path in Google Maps XML format.

=head1 SEE ALSO

L<Geo::Google>

=head1 AUTHOR

Allen Day, E<lt>allenday@ucla.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Allen Day

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
