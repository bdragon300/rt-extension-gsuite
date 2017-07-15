package RT::Extension::GSuite::JWTAuth;

use 5.010;
use strict;
use warnings;

use Mojo::JWT::Google;
use Mojo::Collection;
use Data::Validator;
use Furl;
use JSON;


=head1 NAME

RT::Extension::GSuite::JWTAuth - Implements OAuth 2.0 authorization using JSON Web Token generate

=head1 SYNOPSIS

  use RT::Extension::GSuite::JWTAuth;

  my $request = RT::Extension::GSuite::JWTAuth->new(
    json_file => '/path/to/json/file/with/private/key',
    scopes => ['/first/scope', '/second/scope'],
    token => token hash # Optional
  );

=head1 DESCRIPTION

Package implements OAuth 2.0 authorization using JWT. Stores obtained
access_token inside.

Algo described at: https://developers.google.com/identity/protocols/OAuth2ServiceAccount

Token hash has following keys;

=over

=item * access_token  - access_token value

=item * expires_in - number of seconds in which token is valid

=item * token_type - authorization type, usually 'Bearer'

=item * expires_at - unix time when token will be expired

=back

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 METHODS

=head2 new(json_file, [scopes], [token], [auth_url])

Parameters:

=over

=item json_file - path to the json file with keys and other info

=item scopes - Optional. ARRAYREF, claimed scopes

=item token - Optional. Initial token object

=item auth_url - Optional. URL uses to send auth request. Default: Google Auth

=back

=cut

sub new {
    my $class = shift;
    my %args = (
        json_file => undef,
        scopes => undef,
        token => undef,
        auth_url => q(https://www.googleapis.com/oauth2/v4/token),
        @_
    );

    my $self = {%args};

    bless $self, $class;

    return $self;
}


=head2 token

Current token

=cut

sub token {
    return shift->{token};
}


=head2 generate_token

Generate access_token. Old token will be forgotten

Returns:

Token hash

=cut


sub generate_token {
    my $self = shift;

    undef $self->{token};

    $self->{token} = $self->_generate_token(
        from_json => $self->{json_file},
        target => $self->{auth_url},
        scopes => $self->{scopes}
    );

    return $self->{token};
}


=head2 _generate_token(from_json, target, [scopes])

Implements access_token obtaining process

Parameters:

=over

=item from_json - path to the json file with keys and other info

=item target - authorization URL

=item scopes - Optional. ARRAYREF, claimed scopes

=back

Returns:

Token hash

=cut

sub _generate_token {
    my $self = shift;
    my %args = (
        from_json => undef,
        target => undef,
        scopes => [],
        @_
    );

    $args{set_iat} //= 1;
    $args{scopes} = Mojo::Collection->new( @{$args{scopes}} );

    my $jwt = Mojo::JWT::Google->new(%args);
    $jwt->expires($jwt->now + 300);

    # Send JWT and expect token
    my $req = Furl->new();
    my $params = [
        approval_prompt => 'force',
        grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion => $jwt->encode
    ];
    my $res = $req->post(
        $args{target},
        [],
        $params
    );
    unless ($res->is_success) {
        RT::Logger->error(
            sprintf "[RT::Extension::GSuite]: Error while request access_token: %d %s: %s", 
            $res->code, $res->message,  $res->content
        );
    }

    # Deserialize JSON response
    my $json = undef;
    if ($res->decoded_content) {
        $json = decode_json($res->decoded_content);
    } else {
        RT::Logger->warning("[RT::Extension::GSuite]: " .
            "Unknown charset in auth response, try deserialize without decode"
        );
        $json = decode_json($res->content);
    }

    # Validate JSON
    my $validator = Data::Validator->new(
        access_token => 'Str',
        expires_in => 'Num',
        token_type => 'Str'
    )->with('AllowExtra');
    my ($valid_json, %extra_data) = $validator->validate(%$json);

    # Its ok, return access token
    my $tok = {
        map { $_ => $valid_json->{$_} } qw(access_token expires_in token_type)
    };
    $tok->{expires_at} = time + $tok->{expires_in};

    # Try to shred smth with secret data (not all), IB golovnogo mozga :)
    $self->_shred_string(\$jwt->{'secret'});
    undef $jwt;

    return $tok;
}


=head2 _shred_string(REF)

Shreds memory in given variable with string data.

Parameters:

=over

=item REF - string variable ref

=back

=cut

sub _shred_string {
    my ($self, $ref) = @_;

    if (ref $ref ne 'SCALAR') {
        RT::Logger->error(
            "[RT::Extension::GSuite]: Trying to shred non-scalar ref"
        );
    }
    

    my $l = do { use bytes; length($$ref); };
    substr(
        $$ref, 
        0, 
        $l, 
        chr(int(rand(254))) x $l
    );
}

1;