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

RT::Extension::GSuite::JWTAuth - Implements OAuth 2.0 authorization using JSON Web Token

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

Token hash has following keys:

=over

=item * access_token  - access_token value

=item * expires_in - seconds during which token is valid

=item * token_type - authorization type, usually 'Bearer'

=item * expires_at - unix time when token will be expired

=back

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 METHODS

=head2 new(json_file, scopes=>undef, token=>undef, auth_url=>q(https://www.googleapis.com/oauth2/v4/token))

Parameters:

=over

=item json_file - path to the .json file with private key

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

Current token property

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
        'now' => time,
        scopes => $self->{scopes},
    );

    return $self->{token};
}


=head2 _generate_token(from_json, target, now, scopes=>[], set_iat=>1)

Implements access_token obtaining process

Parameters:

=over

=item from_json - path to the .json file with private key

=item target - authorization URL

=item now - 'NOW' time epoch seconds

=item scopes - Optional. ARRAYREF, claimed scopes

=item set_iat - Optional. If true, then the "iat" claim will be set to 
the "now" value during JWT encode. Default is true.

=back

Returns:

Token hash

=cut

sub _generate_token {
    my $self = shift;
    my %args = (
        from_json => undef,
        target => undef,
        'now' => undef,
        scopes => [],
        set_iat => 1,
        @_
    );

    $args{scopes} = Mojo::Collection->new( @{$args{scopes}} )
        if (ref $args{scopes} eq 'ARRAY');

    my $jwt = $self->_new_jwt(%args);

    # Send JWT and expect token
    my $res = $self->_request($args{target}, $jwt->encode);
    unless ($res->is_success) {
        RT::Logger->error(
            sprintf "[RT::Extension::GSuite]: Error while request access_token: %d %s: %s", 
            $res->code, $res->message,  $res->content
        );
        return 0;
    }

    # Deserialize JSON response
    my $json = $self->_deserialize_response($res);

    # Validate JSON
    my ($valid_json, $extra_data) = $self->_validate_token_response($json);

    # Its ok, return access token
    my $tok = {
        map { $_ => $valid_json->{$_} } qw(access_token expires_in token_type)
    };
    $tok->{expires_at} = $args{'now'} + $tok->{expires_in};

    # Try to shred smth with secret data (not all), IB golovnogo mozga :)
    $self->_shred_string(\$jwt->{'secret'});
    undef $jwt;

    return $tok;
}


=head2 _new_jwt(%ARGS)

Returns new initialized JWT object

Parameters:

=over

=item ARGS - parameters for the constructor

=back

Returns:

Mojo::JWT::Google object

=cut

sub _new_jwt {
    my $self = shift;

    my $jwt = Mojo::JWT::Google->new(@_);
    $jwt->expires($jwt->now + 300);

    return $jwt;
}


=head2 _request(url, assertion, \@params)

Obtains access token by HTTP request from the given url with params

Parameters:

=over

=item url

=item assertion - JWT contents (assertion request parameter)

=item params - Optional. ARRAYREF, additional POST parameters if needed

=back

Returns:

Furl::Response

=cut


sub _request {
    my $self = shift;
    my $url = shift;
    my $assertion = shift;
    my %args = (
        approval_prompt => 'force',
        grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        @_,
        assertion => $assertion
    );
    my $params = [%args]; # ARRAYREF

    my $req = Furl->new();
    my $res = $req->post(
        $url,
        [],
        $params
    );

    return $res;
}


=head2 _deserialize_response(response)

Deserializes json from the response body

Parameters:

=over

=item response - Furl::Response object

=back

Returns:

Deserialized object

=cut


sub _deserialize_response {
    my $self = shift;
    my $response = shift;

    my $json = undef;
    if ($response->decoded_content) {
        $json = decode_json($response->decoded_content);
    } else {
        RT::Logger->warning("[RT::Extension::GSuite]: " .
            "Unknown charset in auth response, try deserialize without decode"
        );
        $json = decode_json($response->content);
    }

    return $json;
}


=head2 _validate_token_response(json)

Performs minimal validation on access token json response

Parameters:

=over

=item json - HASHREF

=back

Returns:

($valid_json, $extra_keys) on success or confess on error

=cut


sub _validate_token_response {
    my $self = shift;
    my $json = shift;

    my $validator = Data::Validator->new(
        access_token => 'Str',
        expires_in => 'Num',
        token_type => 'Str'
    )->with('AllowExtra');
    my ($valid_json, %extra_data) = $validator->validate(%$json);
    undef $validator;

    return ($valid_json, \%extra_data);
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
