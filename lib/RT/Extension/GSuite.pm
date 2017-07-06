package RT::Extension::GSuite;

use 5.010;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT = qw/ load_config load_token store_token check_json_file /;

use Data::Dumper qw(Dumper);
use RT::Extension::GSuite::JWTAuth;

our $VERSION = '0.01';
our $PACKAGE = __PACKAGE__;

=head1 NAME

RT::Extension::GSuite - Working with Google GSuite services from the Request Tracker

=head1 DESCRIPTION

TODO

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item Edit your RT_SiteConfig.pm

If you are using RT 4.2 or greater, add this line:

    Plugin('RT::Extension::RejectUpdate');

For RT 3.8 and 4.0, add this line:

    Set(@Plugins, qw(RT::Extension::RejectUpdate));

or add C<RT::Extension::RejectUpdate> to your existing C<@Plugins> line.

=item Restart your webserver

=back

=head1 CONFIGURATION

See README.md

=head1 AUTHOR

Igor Derkach E<lt>gosha753951@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.


=cut

=head1 ATTRIBUTES

=head2 $available_fields

Hash that describes available fields (besides CustomFields) that can be set by
user in "old state" and "checking fields" sections in configuration. 
<Displaying name> => <%ARGS key> 
Some of these fields are building dynamically such as Transaction.Type

=cut

our %tokens = ();


=head2 load_config

Reads extension config

Receives

None

Returns

=over

=item HASHREF config

=item (undef) if error

=back

=cut

sub load_config 
{
    my %conf = (
       GoogleServiceAccounts => RT->Config->Get('GoogleServiceAccounts'),
       UnsecuredJsonFile => RT->Config->Get('UnsecuredJsonFile') // 0,
    );
    return (undef) if (scalar(grep { ! defined $_ } values %conf));
    return (undef) if ref($conf{'GoogleServiceAccounts'}) ne 'HASH';
    return \%conf;
}



sub check_json_file {
    my ($json_file, $config) = @_;

    # Ensure that json file secured
    unless ($config->{UnsecuredJsonFile}) {
        my $check_perms = 0400;
        my $rt_uid = $>;

        if ( ! -r $json_file) {
            RT::Logger->error(sprintf(
                "[RT::Extension::GSuite]: Cannot read file '%s'. Make sure it readable by RT user with uid %s",
                $json_file, $rt_uid
            ));
            return (undef);
        }

        my @stat = stat($json_file);
        if ($stat[4] != $rt_uid) {
            RT::Logger->error(sprintf(
                "[RT::Extension::GSuite]: Wrong owner uid %s on file %s. Fix it by command: chown %s '%s'",
                $stat[4], $json_file, $rt_uid, $json_file
            ));
            return (undef);
        }
        if (($stat[2] & 0777) != $check_perms) {
            RT::Logger->error(sprintf(
                "[RT::Extension::GSuite]: Insecure permissions %03o on file %s. Fix it by command: chmod %03o '%s'",
                $stat[2] & 0777, $json_file, $check_perms, $json_file
            ));
            return (undef);
        }
    }

    return 1;
}


sub load_token {
    my $name = shift;
    # FIXME: make tokens hash storable permanently
    return $tokens{$name};
}


sub store_token {
    my ($account, $token) = @_;

    $tokens{$account} = $token;
}

1;
