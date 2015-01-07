package McBain;

# ABSTRACT: Framework for building portable, auto-validating and self-documenting APIs

use warnings;
use strict;

use Brannigan;
use Carp;
use File::Spec;

our $VERSION = "3.000000";
$VERSION = eval $VERSION;

our %INFO;

sub import {
	my $target = caller;
	return if $target eq 'main';
	my $me = shift;
	strict->import;
	warnings->import(FATAL => 'all');
	return if $INFO{$target};

	no strict 'refs';

	# find the root of this API (if it's not the current target)
	my $root = _find_root($target);

	if ($target eq $root) {
		unshift(@{"${target}::ISA"}, 'McBain::Topic');

		# create the routes hash for $root
		$INFO{$root} = {};

		# were there any options passed?
		if (scalar @_) {
			my %opts = map { s/^-//; $_ => 1 } @_;
			# apply the options to the root package
			$INFO{$root}->{_opts} = \%opts;
		}
	} else {
		unshift(@{"${target}::ISA"}, ($target =~ m/^(.+)::[^:]+$/)[0]);
	}

	# figure out the topic name from this class
	my $topic = '/';
	unless ($target eq $root) {
		my $rel_name = ($target =~ m/^${root}::(.+)$/)[0];
		$topic = '/'.lc($rel_name);
		$topic =~ s!::!/!g;
	}

	# export the provide subroutine to the target topic,
	# so that it can define routes and methods.
	*{"${target}::provide"} = sub {
		my ($method, $name) = (shift, shift);
		my %opts = @_;

		# make sure the route starts and ends
		# with a slash, and prefix it with the topic
		$name = '/'.$name
			unless $name =~ m{^/};
		$name .= '/'
			unless $name =~ m{/$};
		$name = $topic.$name
			unless $topic eq '/';

		$INFO{$root}->{$name} ||= { _class => $target };
		$INFO{$root}->{$name}->{$method} = \%opts;
	};

	# export shortcuts to the provide() subroutine
	# per http methods
	foreach my $meth (
		[qw/get GET/],
		[qw/put PUT/],
		[qw/post POST/],
		[qw/del DELETE/]
	) {
		*{$target.'::'.$meth->[0]} = sub {
			&{"${target}::provide"}($meth->[1], @_);
		};
	}

	if ($target eq $root && $INFO{$root}->{_opts} && $INFO{$root}->{_opts}->{contextual}) {
		# we're running in contextual mode, which means the API
		# should have a Context class called $root::Context, and this
		# is the class to which we should export the forward() method
		# (the call() method is still exported to the API class).
		# when call() is, umm, called, we need to create a new instance
		# of the context class and use forward() on it to handle the
		# request.
		# we expect this class to be called $root::Context, but if it
		# does not exist, we will try going up the hierarchy until we
		# find one.
		my $ctx = 'McBain::Context'; # the default

		my $check = $root.'::Context';
		while ($check =~ m/::/) {
			eval "require $check";
			if ($@) {
				# go up one level and try again
				$check =~ s/[^:]+::Context$/Context/;
			} else {
				$ctx = $check;
				last;
			}
		}

		$INFO{$root}->{_opts}->{context_class} = $ctx;
	}

	# export the pre_route and post_route "constructors"
	foreach my $mod (qw/pre_route post_route/) {
		*{$target.'::'.$mod} = sub (&) {
			$INFO{$root}->{"_$mod"} ||= {};
			$INFO{$root}->{"_$mod"}->{$topic} = shift;
		};
	}
}

# _find_root( $current_class )
# -- finds the root topic of the API, which might
#    very well be the module we're currently importing into

sub _find_root {
	my $class = shift;

	my $copy = $class;
	while ($copy =~ m/::[^:]+$/) {
		return $`
			if $INFO{$`};
		$copy = $`;
	}

	return $class;
}

1;

package McBain::Topic;

use warnings;
use strict;

use Carp;
use Try::Tiny;
use Moo;

# export the call method, the one that actually
# executes API methods
sub call {
	my ($self, $namespace, $payload, $runner, $runner_data) = @_;

	return try {
		confess { code => 400, error => "Namespace must match <METHOD>:<ROUTE> where METHOD is one of GET, POST, PUT, DELETE or OPTIONS" }
			unless $namespace =~ m/^(GET|POST|PUT|DELETE|OPTIONS):[^:]+$/;

		my ($method, $route) = split(/:/, $namespace);

		# make sure route ends with a slash
		$route .= '/'
			unless $route =~ m{/$};

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

		my @captures;

		my $root = $self->find_root;

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

		# should we create a context object?
		if ($McBain::INFO{$root}->{_opts} && $McBain::INFO{$root}->{_opts}->{contextual}) {
			my $ctx = $McBain::INFO{$root}->{_opts}->{context_class}->new(_api => $self);
			$ctx->can('process_env') && $ctx->process_env($env);
			push(@base_args, $ctx);
		}

		# are there pre_routes?
		foreach my $part (@parts) {
			$McBain::INFO{$root}->{_pre_route}->{$part}->(@base_args, $namespace, $params)
				if $McBain::INFO{$root}->{_pre_route} && $McBain::INFO{$root}->{_pre_route}->{$part};
		}

		# invoke the actual route
		my $res = $r->{$env->{METHOD}}->{cb}->(@base_args, $params, @captures);

		# are there post_routes?
		foreach my $part (@parts) {
			$McBain::INFO{$root}->{_post_route}->{$part}->(@base_args, $namespace, \$res)
				if $McBain::INFO{$root}->{_post_route} && $McBain::INFO{$root}->{_post_route}->{$part};
		}

		return $res;
	} catch {
		# an exception was caught, make sure it's in the standard
		# McBain exception format and rethrow
		if (ref $_ && ref $_ eq 'HASH' && exists $_->{code} && exists $_->{error}) {
			confess $_;
		} else {
			confess { code => 500, error => $_ };
		}
	};
}

# export the is_root() subroutine to the target topic,
# so that it knows whether it is the root of the API
# or not
sub is_root {
	$_[0]->find_root eq ref($_[0]);
}

sub find_root {
	McBain::_find_root(ref($_[0]));
}

# _break_path( $path )
# -- breaks a route/path into a list of "directories",
#    starting from the root and up to the full path

sub _break_path {
	my $path = shift;

	my $copy = $path;

	my @path;

	unless ($copy eq '/') {
		chop($copy);

		while (length($copy)) {
			unshift(@path, $copy);
			$copy =~ s!/[^/]+$!!;
		}
	}

	unshift(@path, '/');

	return @path;
}

sub BUILD {
	my $self = shift;

	# we're done with exporting, now lets try to load all
	# child topics (if any), and collect their method definitions
	my $base = ref($self);
	my $root = $self->find_root;
	my $opts = $McBain::INFO{$root}->{_opts};

	$McBain::INFO{$root}->{_objects} ||= {};
	$McBain::INFO{$root}->{_objects}->{$base} = $self;

	# this code is based on code from Module::Find

	my $pkg_dir = File::Spec->catdir(split(/::/, $base));

	my @inc_dirs = map { File::Spec->catdir($_, $pkg_dir) } @INC;

	foreach my $inc_dir (@inc_dirs) {
		next unless -d $inc_dir;

		opendir DIR, $inc_dir;
		my @pms = grep { !-d && m/\.pm$/ } readdir DIR;
		closedir DIR;

		foreach my $file (@pms) {
			my $pkg = $file;
			$pkg =~ s/\.pm$//;
			$pkg = join('::', File::Spec->splitdir($pkg));

			$pkg = $base.'::'.$pkg;

			my $req = File::Spec->catdir($inc_dir, $file);

			next if $req =~ m!/Context.pm$!
				&& $opts && $opts->{contextual};

			require $req;
			$pkg->new;
		}
	}
}

1;

package McBain::Context;

use Moo;

has '_api' => (
	is => 'ro',
	required => 1
);

sub forward {
	my $self = shift;

	$self->_api->call(@_);
}

1;
__END__
