package McBain::Directly;

use warnings;
use strict;

use Carp;
use JSON;

sub init { 1 }

sub generate_env {
	my $class = shift;

	confess { code => 400, error => "Namespace must match <METHOD>:<ROUTE> where METHOD is one of GET, POST, PUT or DELETE" }
		unless $_[0] =~ m/^(GET|POST|PUT|DELETE):[^:]+$/;

	my ($method, $namespace) = split(/:/, $_[0]);

	return {
		METHOD    => $method,
		NAMESPACE => $namespace,
		PAYLOAD   => $_[1]
	};
}

sub generate_res {
	my ($class, $env, $res) = @_;

	return $res;
}

sub handle_exception {
	confess $_[1];
}

1;
