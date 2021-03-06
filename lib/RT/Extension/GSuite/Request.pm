package RT::Extension::GSuite::Request;

use 5.010;
use strict;
use warnings;

use Furl;
use JSON;
use Sub::Retry;
use URI::Escape qw(uri_escape);
use Data::Dumper qw(Dumper);

=head1 NAME

  RT::Extension::GSuite::Request - Make requests to API using Google Service account (JWT Auth)

=head1 SYNOPSIS

  use RT::Extension::GSuite::Request;

  my $request = RT::Extension::GSuite::Request->new(
    jwtauth => <RT::Extension::GSuite::JWTAuth object>,
    base_url => 'https://www.googleapis.com/...'
  );

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 METHODS

=head2 new(base_url, jwtauth)

Parameters:

=over

=item base_url - base url for requests

=item jwtauth - RT::Extension::GSuite::JWTAuth object

=back

=cut

sub new {
    my $class = shift;
    my %args = (
        base_url => undef,
        jwtauth => undef,
        @_
    );

    my $self = bless {%args}, $class;
    $self->{req} = undef;

    return $self;
}


=head2 login

Logs in Google Account using internal JWTAuth object

Parameters:

No parameters

Returns:

True if login was successfull, false otherwise

=cut

sub login {
    my $self = shift;

    $self->{req} = $self->_login($self->{jwtauth});

    return defined $self->{req};
}


sub _login {
    my ($self, $jwtauth) = @_;

    my $token = $jwtauth->generate_token(); # type: hashref
    unless ($token) {
        RT::Logger->error(
            '[RT::Extension::GSuite]: Unable to obtain access token'
        );
        return (undef);
    }

    return Furl->new(
        headers => [
            'Authorization' => $token->{token_type} . ' ' . $token->{access_token}
        ]
    );
}

=head2 request(method, suburl, params, content=>undef, \%opt=>{})

Makes HTTP request with optional JSON payload

Parameters:

=over

=item method - HTTP method name, e.g. 'GET'

=item suburl - will be concatenated with base url

=item params - query parameters HASHREF

=item content - Optional. Object that will be encoded to JSON and put as request content

=item opt - Optional. HASHREF, {retry_times, retry_interval, headers}

=back

Returns:

=over

=item In list context returns (response_decoded_json, Furl::Response object).

=item In scalar context returns decoded json response only.

=back

=cut

sub request {
    # First version retrieved from Net::Google::Spreadsheets::V4
    my($self, $method, $suburl, $params, $content, $opt, $now) = @_;

    $now //= time;

    unless($self->{req}) {
        RT::Logger->error('[RT::Extension::GSuite]: Request object not logged in');
        return;
    }

    $opt = {
        retry_times    => 3,
        retry_interval => 1.0,
        %{ $opt // {} },
    };

    #$base_url .= '/' if ($base_url !~ /\/$/);  # Append slash  # TODO: one slash between base_url and suburl
    my $url = $self->{base_url} . $suburl;
    if ($params) {
        my %params = map { $_ => uri_escape($params->{$_}) } keys %$params;
        $url .= '?' . join('&', map { $_ . '=' . $params{$_} } keys %params)
            if %params;
    }

    RT::Logger->debug(sprintf(
        "[RT::Extension::GSuite]: request: %s => %s %s %s", 
        $method, $url, Dumper($content//'{no content}', $opt//'no opt')
    ));

    my @headers = ();
    if ($content) {
        push @headers, 'Content-Type' => 'application/json';
    }
    if ($opt->{headers}) {
        push @headers, @{ $opt->{headers} };
    }

    if ( ! $self->{jwtauth}->{token} 
        || $now >= $self->{jwtauth}->{token}->{expires_at})
    {
        return unless $self->login($self->{jwtauth});
    }

    my $res = retry $opt->{retry_times}, $opt->{retry_interval}, sub {
        $self->{req}->request(
            method  => $method,
            url     => $url,
            headers => \@headers,
            $content ? (content => encode_json($content)) : (),
        );
    }, sub {
        my $res = shift;
        if (!$res) {
            RT::Logger->warning("[RT::Extension::GSuite]: not HTTP::Response: $@");
            return 1;
        }

        my $code = $res->code;
        my $line = $res->status_line;
        if ($line =~ /^500\s+Internal Response/
                     or $code =~ /^50[234]$/
                 ) {
            RT::Logger->warning('[RT::Extension::GSuite]: retrying: ' . $line);
            return 1; # do retry
        } elsif ($code == 401) { # Regenerate token
            $self->login($self->{jwtauth});
            return 1;
        } else {
            return;
        }
    };
    
    if ( ! $res) {
        RT::Logger->error(sprintf(
            '[RT::Extension::GSuite]: failure %s %s, %s', 
            $method, $url, Dumper($content//'{no content}')
        ));
        return;
    } else {
        if ($res->is_success) {
            my $res_content = $res->decoded_content ? decode_json($res->decoded_content) : undef;
            return wantarray ? ($res_content, $res) : $res_content;
        } else {
            RT::Logger->error(sprintf(
                '[RT::Extension::GSuite]: failure %s %s, %s => %s, %s', 
                $method, $url, Dumper($content//'{no content}'), $res->status_line, Dumper($res->decoded_content//'{no content}')
            ));
            return wantarray ? (undef, $res) : undef;
        }
    }
}

1;