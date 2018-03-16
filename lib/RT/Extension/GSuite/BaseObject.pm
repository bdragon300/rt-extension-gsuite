package RT::Extension::GSuite::BaseObject;

use 5.010;
use strict;
use warnings;
use Mouse;

=head1 NAME

  RT::Extension::GSuite::BaseObject - Base class for each GSuite entity class

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut


=head1 METHODS

=head2 Get(id) -> boolean

Get object by id. Abstract method

Parameters:

=over

=item $id -- object id

=back

Returns:

Whether operation was successfull

=cut

sub Get {
    die 'Function must be redefined in derived classes';
}

=head2 Reload() -> boolean

Reload current object previoiusly loaded by the same id.
Useful when e.g. request parameters was modified

Parameters:

None

Return:

Whether operation was successfull

=cut

sub Reload {
    my $self = shift;

    unless ($self->id) {
        die '[RT::Extension::GSuite]: Unable to reload object unloaded object';
    }

    $self->Get($self->id);
}


=head2 Create(%args) -> success

Fill out current newly created object with given properties

Parameters:

=over

=item %args -- HASH, properties to fill out

=back

Returns:

None

=cut

sub Create {
    my $self = shift;

    return $self->_FillAttributes(@_);
}


=head2 _FillAttributes(%args) -> success

Util method that fills out object attributes with given values

Parameters:

=over

=item %args -- HASH, properties to fill out

=back

=cut

sub _FillAttributes {
    my $self = shift;
    my %args = (@_);

    $self->{$_} = $args{$_} for keys %args;

    return 1;
}

1;
