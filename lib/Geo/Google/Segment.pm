package Geo::Google::Segment;
use strict;
use warnings;
use Data::Dumper;
use URI::Escape;
our $VERSION = '0.01';

use constant FMT => <<_FMT_;
<segment distance="%s" id="%s" meters="%s" pointIndex="%s" seconds="%s" time="%s">%s</segment>
_FMT_

sub new {
  my $class = shift;
  my %arg = @_;
  my $self = bless \%arg, $class;
}

sub from       { return shift->{'from'} }
sub distance   { return shift->{'distance'} }
sub id         { return shift->{'id'} }
sub meters     { return shift->{'meters'} }
sub pointIndex { return shift->{'pointIndex'} }
sub points     { my $self = shift; return $self->{'points'} ? @{ $self->{'points'} } : () }
sub seconds    { return shift->{'seconds'} }
sub text       { return shift->{'text'} }
sub time       { return shift->{'time'} }
sub to         { return shift->{'to'} }

sub toString {
  my $self = shift;
  return sprintf( FMT,
    $self->distance(),
    $self->id(),
    $self->meters(),
    $self->pointIndex(),
    $self->seconds(),
    $self->time(),
    $self->text(),
  );
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Geo::Google::Segment - An annotated segment of a path

=head1 SYNOPSIS

  use Geo::Google::Segment;
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

Geo::Google::Location objects provide the following accessor methods

 Method      Description
 ------      -----------
 from        a Geo::Google::Location at the beginning of the segment.
 distance    length of the segment, in variable, human friendly units.
 id          a unique identifier for this point.
 meters      length of the segment, in meters.
 pointIndex  the offset, in 0-based points, at which the segment begins
             relative to the start of the path.
 points      a list of Geo::Google::Location points along the segment.
 seconds     a time estimate, in seconds, for how long the segment will
             take to travel by automobile.
 text        a description of the segment, typically some human-readable
             description of this leg of a path, e.g "make a u-turn at
             McLaughlin Ave".
 time        a time estimate, in variable, human-friendly units for how long
             the segment will take to travel by automobile.
 to          a Geo::Google::Location at the end of the segment.
 toString    a method that renders the segment in Google Maps XML format.

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
