package McBain::Directly;

sub init {
}

sub generate_env {
	my $class = shift;

	return {
		METHOD    => 'GET',
		NAMESPACE => $_[0],
		PAYLOAD   => $_[1]
	};
}

sub generate_res {
	my ($class, $env, $res) = @_;

	return $res;
}

1;
