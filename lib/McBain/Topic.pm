package McBain::Topic;

use Brannigan;
use Carp;
use File::Spec;
use Try::Tiny;

use McBain::Mo;

sub call {
	my ($self, $namespace, $payload, $runner, $runner_data) = @_;

	print "Handling request for $namespace from ", $runner || 'Perl', "\n";

	return try {
		confess { code => 400, error => "Namespace must match <METHOD>:<ROUTE> where METHOD is one of GET, POST, PUT, DELETE or OPTIONS" }
			unless $namespace =~ m/^(GET|POST|PUT|DELETE|OPTIONS):([^:]+)$/;

		my ($method, $route) = ($1, $2);

		# make sure route ends with a slash
		$route .= '/'
			unless $route =~ m{/$};

		print "\tCalculated route as $route\n";

		# create the McBain environment hashref
		my $env = {
			METHOD	=> $method,
			ROUTE		=> $route,
			PAYLOAD	=> $payload
		};

		if ($runner) {
			$env->{RUNNER} = $runner;
			$env->{RUNNER_DATA} = $runner_data
				if $runner_data;
		}

		# should we create a context object?
		my $root = McBain::_find_root(ref($self));
		if ($McBain::INFO{$root}->{_opts} && $McBain::INFO{$root}->{_opts}->{contextual}) {
			print "\tCreating object of context class $McBain::INFO{$root}->{_opts}->{context_class}\n";
			my $ctx = $McBain::INFO{$root}->{_opts}->{context_class}->new;
			$ctx->can('process_env') && $ctx->process_env($self, $env);
			$env->{CONTEXT} = $ctx;
		}

		return $self->forward($env);
	} catch {
		# an exception was caught, make sure it's in the standard
		# McBain exception format and rethrow
		my $err = ref $_ && ref $_ eq 'HASH' && exists $_->{code} && exists $_->{error} ?
			$_ :
				{ code => 500, error => $_ };
		
		print "\tException $err->{code} caught: $err->{error}\n";

		confess $err;
	};
}

sub forward {
	my ($self, $env) = @_;

	print "\tForwarding to $env->{ROUTE} with method $env->{METHOD}\n";

	my @captures;

	my $root = McBain::_find_root(ref($self));

	# is there a direct route that equals the request?
	my $r = $McBain::INFO{$root}->{$env->{ROUTE}};

	# if not, is there a regex route that does?
	unless ($r) {
		foreach (keys %{$McBain::INFO{$root}}) {
			next unless @captures = ($env->{ROUTE} =~ m/^$_$/);
			$r = $McBain::INFO{$root}->{$_};
			last;
		}
	}

	confess { code => 404, error => "Route $env->{ROUTE} not found" }
		unless $r;

	# is this an OPTIONS request?
	if ($env->{METHOD} eq 'OPTIONS') {
		my %options;
		foreach my $m (grep { !/^_/ } keys %$r) {
			%{$options{$m}} = map { $_ => $r->{$m}->{$_} } grep($_ ne 'cb', keys(%{$r->{$m}}));
		}
		return \%options;
	}

	# does this route have the HTTP method?
	confess { code => 405, error => "Method $env->{METHOD} not available for route $env->{ROUTE}" }
		unless exists $r->{$env->{METHOD}};

	# process parameters
	my $params = Brannigan::process({ params => $r->{$env->{METHOD}}->{params} }, $env->{PAYLOAD});

	confess { code => 400, error => "Parameters failed validation", rejects => $params->{_rejects} }
		if $params->{_rejects};

	# break the path into "directories", run pre_route methods
	# for each directory (if any)
	my @parts = _break_path($env->{ROUTE});

	# find the topic object
	my @base_args = ($McBain::INFO{$root}->{_objects}->{$r->{_class}});
	push(@base_args, $env->{CONTEXT})
		if $env->{CONTEXT};

	# are there pre_routes?
	foreach (@parts) {
		$McBain::INFO{$root}->{_pre_route}->{$_}->(@base_args, $env->{METHOD}.':'.$env->{ROUTE}, $params)
			if $McBain::INFO{$root}->{_pre_route} && $McBain::INFO{$root}->{_pre_route}->{$_};
	}

	# invoke the actual route
	my $res = $r->{$env->{METHOD}}->{cb}->(@base_args, $params, @captures);

	# are there post_routes?
	foreach (@parts) {
		$McBain::INFO{$root}->{_post_route}->{$_}->(@base_args, $env->{METHOD}.':'.$env->{ROUTE}, \$res)
			if $McBain::INFO{$root}->{_post_route} && $McBain::INFO{$root}->{_post_route}->{$_};
	}

	return $res;
}

sub BUILD {
	my $self = shift;
	my $class = ref $self;

	# create objects for all API topics if we're the root
	if ($class eq McBain::_find_root($class)) {
		$McBain::INFO{$class}->{_objects} = { $class => $self };

		foreach (sort grep { $_ ne $class } keys %{$McBain::INFO{$class}->{_topics}}) {
			$McBain::INFO{$class}->{_objects}->{$_} = $_->new;
		}
	}
}

# _break_path( $path )
# -- breaks path into list of "directories", starting from the root and up to the full path

sub _break_path {
	$_[0] ? (_break_path($_[0] =~ m!^(.+/)[^/]+!), substr($_[0], 0, -1)) : ('/');
}

1;
__END__
