use strict;
use warnings;

no warnings 'redefine';

use RT::Extension::GSuite::Test
    testing => 'RT::Extension::GSuite::Request',
    tests => undef;
use Test::MockObject;
use Test::MockObject::Extends;
use RT;
use JSON;
use Data::Dumper qw(Dumper);

use namespace::autoclean;

use_ok('RT::Extension::GSuite::Request');

my %initial_data = (
    base_url => 'test_base_url',
    jwtauth => undef
);

my %test_token = (
    access_token => 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3',
    expires_in => 3600,
    token_type => 'Bearer',
    expires_at => time + 3600
);


sub main_mock {
    $initial_data{jwtauth} = Test::MockObject->new();

    my $o = RT::Extension::GSuite::Request->new(%initial_data);
    my $m = Test::MockObject::Extends->new($o);

    # Mock RT::Logger methods to avoid warnings
    my $logger_mock = Test::MockObject::Extends->new($RT::Logger);
    map { $logger_mock->set_true($_) } qw(error warning info debug log);
    $RT::Logger = $logger_mock;

    return $m;
}

sub furl_mock {
    my ($mock, $test_response) = @_;

    my $response_mock = Test::MockObject->new();
    $response_mock
        ->set_always('decoded_content', $test_response)
        ->set_always('status_line', '200 OK')
        ->set_always('code', 200)
        ->set_true('is_success');

    my $fmock = Test::MockObject->new();
    $fmock->set_always('request', $response_mock);
    $mock->{req} = $fmock;

    return wantarray ? ($fmock, $response_mock) : $fmock;
}


subtest 'test_initial_req' => sub {
    my $m = main_mock();

    #
    #

    ok( exists $m->{req} && ! defined $m->{req});
};


subtest 'test_initial_jwtauth' => sub {
    my $m = main_mock();

    #
    #

    isa_ok($m->{jwtauth}, 'Test::MockObject');
};


subtest 'test_login' => sub {
    my $m = main_mock();
    $m->set_true('_login');

    #
    my $res = $m->login();
    #

    ok($res);
    is_deeply([$m->call_args(1)], [$m, $m->{jwtauth}]);
};


subtest 'test__login_return_furl_obj_on_success' => sub {
    my $m = main_mock();
    $m->{jwtauth}->set_always('generate_token', \%test_token);

    my $furl_mock = Test::MockObject->new();
    $furl_mock->fake_new('Furl');

    #
    my $res = $m->_login($m->{jwtauth});
    #

    is($res, $furl_mock);
    # is_deeply([$furl_mock->call_args(0)], [
    #     $furl_mock,
    #     headers => ['Authorization', sprintf('%s %s', $test_token{token_type}, $test_token{access_token})]
    # ]);
};


subtest 'test__login_return_undef_on_fail' => sub {
    my $m = main_mock();
    $m->{jwtauth}->set_false('generate_token');

    #
    my $res = $m->_login($m->{jwtauth});
    #

    ok( ! defined $res);
};


subtest 'test_request_return_scalar_undef_on_not_logged_in' => sub {
    my $m = main_mock();
    my @test_params = ('GET' => 'test_suburl');

    #
    my $res = $m->request(@test_params);
    #

    ok( ! defined $res);
};


subtest 'test_request_return_list_undef_on_not_logged_in' => sub {
    my $m = main_mock();
    my @test_params = ('GET' => 'test_suburl');

    #
    my @res = $m->request(@test_params);
    #

    ok( ! @res );
};


subtest 'test_request_return_scalar_response_content' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{"test": "response"}';
    my $check_response = {'test' => 'response'};

    my $fm = furl_mock($m, $test_response);
    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    is_deeply([$fm->call_args(0)], [
        $fm,
        method => $test_params[0],
        url => $m->{base_url} . $test_params[1],
        headers => [],
        ()
    ]);
    is_deeply($res, $check_response);
};


subtest 'test_request_return_list_response_content_and_request_object' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{"test": "response"}';
    my $check_response = {'test' => 'response'};

    my ($fm, $response_mock) = (furl_mock($m, $test_response));
    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my @res = $m->request(@test_params);
    #

    is_deeply([$fm->call_args(0)], [
        $fm,
        method => $test_params[0],
        url => $m->{base_url} . $test_params[1],
        headers => [],
        ()
    ]);
    is_deeply([@res], [$check_response, $response_mock]);
};


subtest 'test_request_return_undef_response_on_no_decoded_content' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{"test": "response"}';
    my $check_response = undef;

    my $fm = furl_mock($m, undef);
    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    is_deeply([$fm->call_args(0)], [
        $fm,
        method => $test_params[0],
        url => $m->{base_url} . $test_params[1],
        headers => [],
        ()
    ]);
    is_deeply($res, $check_response);
};


subtest 'test_request_add_content_type_header_if_request_content_not_empty' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_request_content_hash = {'test' => 'request'};
    my $test_request_content = encode_json($test_request_content_hash);
    my $test_response = '{"test": "response"}';
    my $check_response = {'test' => 'response'};

    my $fm = furl_mock($m, $test_response);
    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', $test_request_content_hash, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    is_deeply($res, $check_response);
    is_deeply([$fm->call_args(0)], [
        $fm,
        method => $test_params[0],
        url => $m->{base_url} . $test_params[1],
        headers => ['Content-Type' => 'application/json'], # this one
        content => $test_request_content
    ]);
};


subtest 'test_request_relogin_when_token_expired' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{}';
    my $check_response = {};

    my $fm = furl_mock($m, $test_response);
    $m->{req} = $fm;

    $m->set_true('login');

    my $now = $test_token{expires_at} + 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    is_deeply([$m->call_args(1)], [ # _login
        $m,
        $m->{jwtauth}
    ]);
};


subtest 'test_request_undef_on_relogin_failed_when_token_expired' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{}';
    my $check_response = {};

    my $fm = furl_mock($m, $test_response);

    $m->set_false('login');

    my $now = $test_token{expires_at} + 1;

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    ok( ! defined $res);
};


subtest 'test_request_retry_on_http_50x' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{}';
    my $check_response = {};

    my @mocks = furl_mock($m, $test_response); #furl, response
    my ($fm, $rm) = @mocks;
    $rm->set_series('status_line', ('500 Internal', '200 OK'));
    $rm->set_series('code', (500, 200));

    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    is($fm->call_pos(0), 'request');
    is($fm->call_pos(1), 'request');
};


subtest 'test_request_retry_relogin_on_http_401' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{}';
    my $check_response = {};

    my @mocks = furl_mock($m, $test_response); #furl, response
    my ($fm, $rm) = @mocks;
    $rm->set_series('status_line', ('401 Unauthorized', '200 OK'));
    $rm->set_series('code', (401, 200));

    $m->set_always('_login', $fm);

    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    is($m->call_pos(1), '_login');
};

subtest 'test_request_retry_on_response_is_undef' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{}';
    my $check_response = {};

    my @mocks = furl_mock($m, $test_response); #furl, response
    my ($fm, $rm) = @mocks;
    $fm->set_series('request', (undef, $rm));

    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    is($fm->call_pos(0), 'request');
    is($fm->call_pos(1), 'request');
};


subtest 'test_request_return_undef_if_response_still_undef' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{}';
    my $check_response = {};

    my @mocks = furl_mock($m, $test_response); #furl, response
    my ($fm, $rm) = @mocks;
    $fm->set_false('request');

    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    ok( ! $res);
};


subtest 'test_request_return_undef_if_response_still_failed' => sub {
    my $m = main_mock();
    $m->{jwtauth} = {token => \%test_token};

    my $test_response = '{}';
    my $check_response = {};

    my @mocks = furl_mock($m, $test_response); #furl, response
    my ($fm, $rm) = @mocks;
    $rm->set_false('is_success');
    $rm->set_always('code', 404);
    $rm->set_always('status_line', '404 Not Found');

    my $now = $test_token{expires_at} - 1;

    *RT::Extension::GSuite::Request::decode_json = sub { $check_response; };
    &RT::Extension::GSuite::Request::decode_json;  # prevent warning 'used only once'

    my @test_params = ('GET' => 'test_suburl', undef, undef, $now);

    #
    my $res = $m->request(@test_params);
    #

    ok( ! defined $res);
};


done_testing();
