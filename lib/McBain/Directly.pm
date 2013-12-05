package McBain::Directly;

use warnings;
use strict;

use Carp;

sub init { 1 }

sub generate_env {
	my $class = shift;

	croak "400 Bad Request"
		unless $_[0] =~ m/^(GET|POST|PUT|DELETE):/;

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

1;
