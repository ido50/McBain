package McBain;

# ABSTRACT: Framework for building portable, auto-validating and self-documenting APIs

use warnings;
use strict;

use Brannigan;
use Carp;
use File::Spec;
use Try::Tiny;

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

	# find the root of this API (if it's not the current target)
	my $root = _find_root($target);

	# create the routes hash for $root
	$INFO{$root} ||= {};

	# were there any options passed?
	if (scalar @_) {
		my %opts = map { s/^-//; $_ => 1 } @_;
		# apply the options to the root package
		$INFO{$root}->{_opts} = \%opts;
	}

	# figure out the topic name from this class
	my $topic = '/';
	unless ($target eq $root) {
		my $rel_name = ($target =~ m/^${root}::(.+)$/)[0];
		$topic = '/'.lc($rel_name);
		$topic =~ s!::!/!g;
	}

	no strict 'refs';

	# export the is_root() subroutine to the target topic,
	# so that it knows whether it is the root of the API
	# or not
	*{"${target}::is_root"} = sub {
		exists $INFO{$target};
	};

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

	my $forward_target = $target;

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
		my $check = $root.'::Context';
		my $ft;
		while ($check) {
			eval "require $check";
			if ($@) {
				# go up one level and try again
				$check =~ s/[^:]+::Context$/Context/;
			} else {
				$ft = $check;
				last;
			}
		}

		croak "No context class found"
			unless $ft;
		croak "Context class doesn't have create_from_env() method"
			unless $ft->can('create_from_env');

		$forward_target = $ft;
	}

	# export the pre_route and post_route "constructors"
	foreach my $mod (qw/pre_route post_route/) {
		*{$target.'::'.$mod} = sub (&) {
			$INFO{$root}->{"_$mod"} ||= {};
			$INFO{$root}->{"_$mod"}->{$topic} = shift;
		};
	}

	if ($target eq $root) {
		# export the call method, the one that actually
		# executes API methods
		*{"${target}::call"} = sub {
			my ($self, @args) = @_;

			return try {
				confess { code => 400, error => "Namespace must match <METHOD>:<ROUTE> where METHOD is one of GET, POST, PUT, DELETE or OPTIONS" }
					unless $args[0] =~ m/^(GET|POST|PUT|DELETE|OPTIONS):[^:]+$/;

				my ($method, $route) = split(/:/, $args[0]);

				my $env = {
					METHOD	=> $method,
					ROUTE		=> $route,
					PAYLOAD	=> $args[1]
				};

				my $ctx = $INFO{$root}->{_opts} && $INFO{$root}->{_opts}->{contextual} ?
					$forward_target->create_from_env('McBain::Directly', $env, @args) :
						$self;

				# handle the request
				return $ctx->forward($env->{METHOD}.':'.$env->{ROUTE}, $env->{PAYLOAD});
			} catch {
				# an exception was caught, make sure it's in the standard
				# McBain exception format and rethrow
				if (ref $_ && ref $_ eq 'HASH' && exists $_->{code} && exists $_->{error}) {
					confess $_;
				} else {
					confess { code => 500, error => $_ };
				}
			};
		};

		# export the forward method, which is both used internally
		# in call(), and can be used by API authors within API
		# methods
		*{"${forward_target}::forward"} = sub {
			my ($ctx, $meth_and_route, $payload) = @_;

			my ($meth, $route) = split(/:/, $meth_and_route);

			# make sure route ends with a slash
			$route .= '/'
				unless $route =~ m{/$};

			my @captures;

			# is there a direct route that equals the request?
			my $r = $INFO{$root}->{$route};

			# if not, is there a regex route that does?
			unless ($r) {
				foreach (keys %{$INFO{$root}}) {
					next unless @captures = ($route =~ m/^$_$/);
					$r = $INFO{$root}->{$_};
					last;
				}
			}

			confess { code => 404, error => "Route $route not found" }
				unless $r;

			# is this an OPTIONS request?
			if ($meth eq 'OPTIONS') {
				my %options;
				foreach my $m (grep { !/^_/ } keys %$r) {
					%{$options{$m}} = map { $_ => $r->{$m}->{$_} } grep($_ ne 'cb', keys(%{$r->{$m}}));
				}
				return \%options;
			}

			# does this route have the HTTP method?
			confess { code => 405, error => "Method $meth not available for route $route" }
				unless exists $r->{$meth};

			# process parameters
			my $params_ret = Brannigan::process({ params => $r->{$meth}->{params} }, $payload);

			confess { code => 400, error => "Parameters failed validation", rejects => $params_ret->{_rejects} }
				if $params_ret->{_rejects};

			# break the path into "directories", run pre_route methods
			# for each directory (if any)
			my @parts = _break_path($route);

			# find the topic object (or create it if it doesn't exist yet)
			$r->{_object} ||= $r->{_class}->new;

			# are there pre_routes?
			my @base_args = ($r->{_object});
			push(@base_args, $ctx)
				if $INFO{$root}->{_opts} && $INFO{$root}->{_opts}->{contextual};

			foreach my $part (@parts) {
				$INFO{$root}->{_pre_route}->{$part}->(@base_args, $meth_and_route, $params_ret)
					if $INFO{$root}->{_pre_route} && $INFO{$root}->{_pre_route}->{$part};
			}

			my $res = $r->{$meth}->{cb}->(@base_args, $params_ret, @captures);

			# are there post_routes?
			foreach my $part (@parts) {
				$INFO{$root}->{_post_route}->{$part}->(@base_args, $meth_and_route, \$res)
					if $INFO{$root}->{_post_route} && $INFO{$root}->{_post_route}->{$part};
			}

			return $res;
		};
	} else {
		# make the target inherit its parent
		unshift(@{"${target}::ISA"}, ($target =~ m/^(.+)::[^:]+$/)[0]);
	}

	# we're done with exporting, now lets try to load all
	# child topics (if any), and collect their method definitions
	_load_topics($target, $INFO{$root}->{_opts});
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

# _load_topics( $base, [ \%opts ] )
# -- finds and loads the child topics of the class we're
#    currently importing into, automatically requiring
#    them and thus importing McBain into them as well

sub _load_topics {
	my ($base, $opts) = @_;

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

			my $req = File::Spec->catdir($inc_dir, $file);

			next if $req =~ m!/Context.pm$!
				&& $opts && $opts->{contextual};

			require $req;
		}
	}
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

1;
__END__
