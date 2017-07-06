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

RT::Extension::GSuite - Google GSuite services for the Request Tracker

=head1 DESCRIPTION

The extension allows to work with Google GSuite products from Request Tracker
Scrips. Uses Google API v4 with JWT authorization (Google Service Account).

Work approach: create Scrip, that runs Action from this extension
(GoogleSheet for example) and write Template, which contains work logic. Set
config headers inside Template. When Template code executes, it's standart 
context complements by API object variables ($Sheet for example) through which
you can work with API or raw data if you want only read/write smth for example.

See appropriate modules docs.

The extension supports many service accounts with their json files. Authorization
uses JSON Web Token when Google doesn't confirm user to access requested
priviledges. Google recommends this method for Server-to-Server communication
without user participation. More: https://developers.google.com/identity/protocols/OAuth2

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

=item Apply initialdata if needed C<make initdb>

Be careful, run the last command one time only, otherwise you can get duplicates
in the database.

May need root permissions

=item Add line to your RT_SiteConfig.pm

    Plugin('RT::Extension::GSuite');

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


# name => token_hash
# each token hash keys -- see RT::Extension::GSuite::JWTAuth docs
our %tokens = ();


=head1 METHODS

=head2 load_config

Reads extension config

Parameters:

None

Returns:

=over

=item HASHREF config

=item (undef) if error

=back

=cut

sub load_config 
{
    my %conf = (
       GoogleServiceAccounts => RT->Config->Get('GoogleServiceAccounts'),
       InsecureJsonFile => RT->Config->Get('InsecureJsonFile') // 0,
    );
    return (undef) if (scalar(grep { ! defined $_ } values %conf));
    return (undef) if ref($conf{'GoogleServiceAccounts'}) ne 'HASH';
    return \%conf;
}


=head2 check_json_file(json_file)

Checks key json file permissions. Writes msg to the log

Parameters:

=over

=item json_file - key json file name

=back

Returns:

1 on success, undef on fail

=cut

sub check_json_file {
    my ($json_file, $config) = @_;

    my $rt_uid = $>; # Effective uid

    if ( ! -r $json_file) {
        RT::Logger->error(sprintf(
            "[RT::Extension::GSuite]: Cannot read file '%s'. Make sure it readable by RT user with uid %s",
            $json_file, $rt_uid
        ));
        return (undef);
    }

    # Ensure that json file is secure
    my $check_perms = 0400; # r--------
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

    return 1;
}


=head2 load_token(name)

Loads cached token by account name

Parameters:

=over

=item name - service account name

=back

Returns:

token HASHREF, undef if not found

=cut

sub load_token {
    my $name = shift;
    # FIXME: make tokens hash storable permanently, %tokens is useless now
    return $tokens{$name};
}


=head2 store_token(name, token)

Writes token to the cache

Parameters:

=over

=item name - service account name

=item token - token HASHREF

=back

=cut

sub store_token {
    my ($account, $token) = @_;

    $tokens{$account} = $token;
}

1;
