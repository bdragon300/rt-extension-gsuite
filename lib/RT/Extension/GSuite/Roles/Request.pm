package RT::Extension::GSuite::Roles::Request;

use 5.010;
use strict;
use warnings;
use Mouse::Role;

=head1 NAME

  RT::Extension::GSuite::Role::Request - Role (mixin) to all GSuite entity 
  classes to be able perform requests

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=cut

=head1 ATTRIBUTES

=head2 request_obj

RT::Extension::GSuite::Request object, required. Initialized by constructor

=cut

has request_obj => (
    required => 1,
    is => 'ro'
);


=head2 suburl

Relative URL to make request

=cut

has suburl => (
    is => 'rw',
    required => 1
);


=head1 METHODS

=head2 _Request(@ARGS) -> ($deserialized_content, $response_obj)

Google API request helper method. Performs request and handles errors

Parameters:

(method, suburl, content, params, opt). See RT::Extension::GSuite::Request::request docs

Returns:

=over

=item ARRAYREF|HASHREF -- deserialized JSON response

=item Furl::Response object

=back

=cut

sub _Request {
    my $self = shift;

    my ($content, $res) = $self->request_obj->request(@_);
    unless ($res->is_success) {
        RT::Logger->error(
            '[RT::Extension::GSuite]: Google API request failed: ' 
            . $res->request->request_line . ' => ' . $res->status 
            . ': ' . $res->message);
    }

    return ($content, $res);
}

1;
