package McBain::WithPSGI;

use warnings;
use strict;

use JSON;
use Plack::Request;

sub init {
	my ($class, $target) = @_;

	no strict 'refs';
	push(@{"${target}::ISA"}, 'Plack::Component');
}

sub generate_env {
	my ($self, $psgi_env) = @_;

	my $req = Plack::Request->new($psgi_env);

	return {
		METHOD => $req->method,
		NAMESPACE => $req->path,
		PAYLOAD => $req->content ? decode_json($req->content) : {}
	};
}

sub generate_res {
	my ($self, $env, $res) = @_;

	$res = { $env->{NAMESPACE} => $res }
		unless ref $res eq 'HASH';

	return [200, ['Content-Type' => 'application/json; charset=UTF-8'], [encode_json($res)]];
}

1;
