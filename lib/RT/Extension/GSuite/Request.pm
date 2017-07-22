package RT::Extension::GSuite::Request;

use 5.010;
use strict;
use warnings;

use Furl;
use JSON;
use Sub::Retry;
use Data::Dumper qw(Dumper);

=head1 NAME

  RT::Extension::GSuite::Request - Make requests to API using Google Service account (JWT Auth)

=head1 SYNOPSIS

  use RT::Extension::GSuite::Request;

  my $request = RT::Extension::GSuite::Request->new(
    jwtauth => <RT::Extension::GSuite::JWTAuth object>,
    base_url => 'https://www.googleapis.com/...'
  );

=head1 DESCRIPTION

  Package makes requests to the API. Object constructor accepts RT::Extension::GSuite::JWTAuth
  object that stores access_token and generates new one if expired.

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 METHODS

=head2 new(base_url, jwtauth)

Creates Request object. Call 'login' before any operation

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

Makes login process using JWTAuth object passed on create

Parameters:

No parameters

Returns:

True if login was successfull, false otherwise

=cut

sub login {
    my $self = shift;

    $self->{req} = $self->_gen($self->{jwtauth});

    return defined $self->{req};
}


sub _gen {
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

=head2 request(method, suburl, [content], [opt])

Makes HTTP request with JSON payload

Parameters:

=over

=item method - HTTP method name, e.g. 'GET'

=item suburl - will be concatenated with base url

=item content - Optional. Will be encoded to JSON and put as request content

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
    my($self, $method, $suburl, $content, $opt) = @_;

    unless($self->{req}) {
        RT::Logger->error('[RT::Extension::GSuite]: Request object not logged in');
        return wantarray ? ('', $res) : '';
    }

    $opt = {
        retry_times    => 3,
        retry_interval => 1.0,
        %{ $opt // {} },
    };

    #$base_url .= '/' if ($base_url !~ /\/$/);  # Append slash
    my $url = $self->{base_url} . $suburl;

    RT::Logger->debug(sprintf(
        "[RT::Extension::GSuite]: request: %s => %s %s %s", 
        $method, $url, Dumper($content//'{no content}', $opt//'no opt')
    ));

    my @headers = [];
    if ($content) {
        push @headers, 'Content-Type' => 'application/json';
    }
    if ($opt->{headers}) {
        push @headers, @{ $opt->{headers} };
    }

    if ( ! $self->{jwtauth}->{token} 
        || time >= $self->{jwtauth}->{token}->{expires_at})
    {
        $self->{req} = $self->_gen($self->{jwtauth});
        return (undef) unless $self->{req};
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
        } elsif ($res->status_line =~ /^500\s+Internal Response/
                     or $res->code =~ /^50[234]$/
                 ) {
            RT::Logger->warning('[RT::Extension::GSuite]: retrying:' 
                . $res->status_line);
            return 1; # do retry
        } elsif ($res->code == 401) { # Regenerate token
            $self->{req} = $self->_gen($self->{jwtauth});
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
                $method, $url, Dumper($content//'{no content}'), $res->status_line, $res->content
            ));
            return wantarray ? ('', $res) : '';
        }
    }
}

1;