package Geo::Google::Location;
use strict;
use warnings;
use Data::Dumper;
use URI::Escape;
our $VERSION = '0.01';

use constant FMT => <<_FMT_;
<location infoStyle="%s" id="%s">
  <point lat="%s" lng="%s"/>
  <icon image="%s" class="local"/>
  <info>
    <address>
      %s
    </address>
  </info>
</location>
_FMT_

#      $loc->{'latitude'} = $lat;
#      $loc->{'longitude'} = $lng;
#      $loc->{'lines'} = [@lines];
#      $loc->{'id'} = $id;
#      $loc->{'icon'} = $icon;
#      $loc->{'infostyle'} = $infoStyle;

sub new {
  my $class = shift;
  my %arg = @_;
  my $self = bless \%arg, $class;
}

sub icon      { return shift->{'icon'} }
sub id        { return shift->{'id'} }
sub infostyle { return shift->{'infostyle'} }
sub latitude  { return shift->{'latitude'} }
sub lines     { my $self = shift; return $self->{'lines'} ? @{ $self->{'lines'} } : () }
sub longitude { return shift->{'longitude'} }
sub title     { return shift->{'title'} }

sub toString {
  my $self = shift;
  return sprintf( FMT,
    $self->infostyle(),
    $self->id(),
    $self->latitude(),
    $self->longitude(),
    $self->icon(),
    join('',map {"<line>$_</line>"} $self->lines() ),
  );
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Geo::Google::Location - A geographical point

=head1 SYNOPSIS

  use Geo::Google::Point;
  # you shouldn't need to construct these yourself,
  # have a Geo::Google object do it for you. 

=head1 DESCRIPTION

=head1 OBJECT METHODS

Geo::Google::Location objects provide the following accessor methods

 Method      Description
 ------      -----------
 icon        an icon to use when drawing this point.
 id          a unique identifier for this point.
 infostyle   unknown function.
 latitude    latitude of the point, to hundred-thousandth degree precision.
 lines       a few lines describing the point, useful as a label
 longitude   longitude of the point, to hundred-thousandth degree precision.
 title       a concise description of the point.
 toString    a method that renders the point in Google Maps XML format.

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
