use strict;
use warnings;

use RT::Extension::GSuite::Test
    testing => 'RT::Extension::GSuite::JWTAuth',
    tests => undef;
use Test::MockObject;
use Test::MockObject::Extends;
use Mojo::Collection;
use RT;
use JSON;

use namespace::autoclean;

use_ok('RT::Extension::GSuite::JWTAuth');

my %initial_data = (
    json_file => 'test_json_file',
    scopes => ['test', 'scopes'],
    token => 'test_token',
    auth_url => 'test_auth_url'
);

my %test_access_token_response = (
    access_token => 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3',
    expires_in => 3600,
    token_type => 'Bearer',
);
my $test_access_token_response_json = encode_json(\%test_access_token_response);


sub main_mock { 
    my $o = RT::Extension::GSuite::JWTAuth->new(%initial_data);
    my $m = Test::MockObject::Extends->new($o);

    # JWTAuth uses RT::Logger
    my $logger_mock = Test::MockObject::Extends->new($RT::Logger);
    map { $logger_mock->set_true($_) } qw(error warning info debug log);
    $RT::Logger = $logger_mock;

    return $m;
}


subtest 'test_generate_token' => sub {
    my $m = main_mock();
    $m->set_always('_generate_token', \%test_access_token_response);

    my $test_time = time;
    *RT::Extension::GSuite::JWTAuth::time = sub { $test_time; };
    &RT::Extension::GSuite::JWTAuth::time;  # prevent warning 'used only once'

    my $res = $m->generate_token();

    is_deeply([$m->call_args(1)], [
        $m,
        from_json => $initial_data{json_file},
        target => $initial_data{auth_url},
        'now' => $test_time,
        scopes => $initial_data{scopes}
    ]);
    is_deeply($res, \%test_access_token_response);
};


subtest 'test__generate_token_return_value' => sub {
    my $m = main_mock();
    my $test_time = time;
    my %test_generated_token = (
        %test_access_token_response,
        expires_at => $test_time + $test_access_token_response{expires_in}
    );
    my $jwt_mock = Test::MockObject->new();
    $jwt_mock->set_always('encode', 'JWT assertion here');
    $m->set_always('_new_jwt', $jwt_mock);

    my $request_mock = Test::MockObject->new();
    $request_mock
        ->set_true('is_success');
    $m->set_always('_request', $request_mock);

    $m->set_always('_deserialize_response', \%test_generated_token);
    $m->set_always('_validate_token_response', (\%test_generated_token, ()));
    $m->set_true('_shred_string');

    my %test_args = (
        from_json => $initial_data{json_file},
        target => $initial_data{auth_url},
        'now' => $test_time,
        scopes => $initial_data{scopes},
        set_iat => 0
    );

    #
    my $res = $m->_generate_token(%test_args);
    #

    is_deeply($res, \%test_generated_token);
};


subtest 'test__generate_token_arrayref_convert_to_mojo_collection' => sub {
    my $m = main_mock();
    $m->mock('_new_jwt', sub {die;});

    eval {
        $m->_generate_token(scopes=>[1,2,3]);
    };

    my ($s, %a) = $m->call_args(1);
    isa_ok($a{scopes}, 'Mojo::Collection');
};


subtest 'test__generate_token_jwt_parameters' => sub {
    my $m = main_mock();
    $m->mock('_new_jwt', sub {die;});
    my %test_args = (
        from_json => $initial_data{json_file},
        target => $initial_data{auth_url},
        set_iat => 0
        # scopes list becomes Mojo::Collection
    );

    #
    eval {
        my $res = $m->_generate_token(%test_args);
    };
    #
    
    my ($s, %a) = $m->call_args(0);
    is_deeply({%a{keys %test_args}}, \%test_args);
};


subtest 'test__generate_token_return_0_if_request_failed' => sub {
    my $m = main_mock();
    my $jwt_mock = Test::MockObject->new();
    $jwt_mock->set_always('encode', 'JWT assertion here');
    $m->set_always('_new_jwt', $jwt_mock);

    my $request_mock = Test::MockObject->new();
    $request_mock
        ->set_false('is_success')
        ->set_always('code', 400)
        ->set_always('message', 'test message')
        ->set_always('content', 'test content');
    $m->set_always('_request', $request_mock);

    my %test_args = (
        from_json => $initial_data{json_file},
        target => $initial_data{auth_url},
        set_iat => 0
    );

    #
    my $res = $m->_generate_token(%test_args);
    #

    ok( ! $res);
};

subtest 'test__new_jwt' => sub {
    my $m = main_mock();
    my $now = time;

    my $jwt_google_mock = Test::MockObject->new();
    $jwt_google_mock->fake_new('Mojo::JWT::Google');
    $jwt_google_mock
        ->set_true('expires')
        ->set_always('now', $now);

    #
    my $res = $m->_new_jwt();
    #

    is($res, $jwt_google_mock);
    is_deeply([$jwt_google_mock->call_args(2)], [ # 'expires'
        $jwt_google_mock,
        $now + 300
    ]);
};

subtest 'test__request' => sub {
    my $m = main_mock();

    my $furl_mock = Test::MockObject->new();
    $furl_mock->fake_new('Furl');
    $furl_mock
        ->set_always('post', $test_access_token_response_json);

    my $test_assertion = 'test_assertion';
    my $test_url = 'test_url';
    my %test_args = (
        assertion => 'doesnt_matter',  # Overwrites by 'assertion' arg
        grant_type => 'test_grant_type',
        extra_parameter => 'test_extra'
    );
    my %check_post_args = (
        approval_prompt => 'force',
        grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        %test_args,
        assertion => $test_assertion
    );

    #
    my $res = $m->_request($test_url, $test_assertion, %test_args);
    #

    is($res, $test_access_token_response_json);
    my @call_args = $furl_mock->call_args(1); # post
    is($call_args[1], $test_url);
    is_deeply($call_args[2], []);
    is_deeply({@{$call_args[3]}}, \%check_post_args);
};


subtest 'test__deserialize_response_decoded' => sub {
    my $m = main_mock();
    my $response_mock = Test::MockObject->new();
    $response_mock->set_always('decoded_content', $test_access_token_response_json);

    #
    my $res = $m->_deserialize_response($response_mock);
    #

    is_deeply($res, \%test_access_token_response);
};


subtest 'test__deserialize_response_no_decoded' => sub {
    my $m = main_mock();
    my $response_mock = Test::MockObject->new();
    $response_mock
        ->set_false('decoded_content')
        ->set_always('content', $test_access_token_response_json);

    #
    my $res = $m->_deserialize_response($response_mock);
    #

    is_deeply($res, \%test_access_token_response);
};


subtest 'test__validate_token_response_correct_returned' => sub {
    my $m = main_mock();
    my %test_data = (
        %test_access_token_response,
        extra_key => 'extra_value'
    );
    my %check_data = %test_access_token_response;

    #
    my ($res, $extra) = $m->_validate_token_response(\%test_data);
    #

    is_deeply($res, \%check_data);
};


subtest 'test__validate_token_response_extra_returned' => sub {
    my $m = main_mock();
    my %test_data = (
        %test_access_token_response,
        extra_key => 'extra_value'
    );
    my %check_data = (
        extra_key => 'extra_value'
    );

    #
    my ($res, $extra) = $m->_validate_token_response(\%test_data);
    #

    is_deeply($extra, \%check_data);
};


subtest '_shred_string' => sub {
    my $m = main_mock();
    my $test_data = 'test_data';
    my $test_address = \$test_data;
    my $check_data = 'test_data';
    my $check_address = \$test_data;

    #
    $m->_shred_string($test_address);
    #

    is($test_address, $check_address);
    isnt($test_data, $check_data);
    cmp_ok(length $test_data, '==', length $check_data);
};

done_testing();
