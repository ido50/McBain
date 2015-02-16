package McBain;

# ABSTRACT: Framework for building portable, auto-validating and self-documenting APIs

use warnings;
use strict;

use Carp;
use McBain::Topic;

our $VERSION = "3.000000";
$VERSION = eval $VERSION;

our %INFO;

sub import {
	my $target = caller;
	return if $target eq 'main' || $INFO{$target};

	no strict 'refs';

	# find the root of this API (if it's not the current target)
	my $root = _find_root($target);

	# were there any options passed?
	my %_opts = map { (my $o = $_) =~ s/^-//; $o => 1 } @_;

	if ($target eq $root) {
		unshift(@{"${target}::ISA"}, 'McBain::Topic');

		# create the routes hash for $root
		$INFO{$root} = { _topics => {} };

		$INFO{$root}->{_opts} = \%_opts
			if %_opts;
	} else {
		unshift(@{"${target}::ISA"}, ($target =~ m/^(.+)::[^:]+$/)[0]);
	}

	# figure out the topic name from this class
	my $topic = '/';
	unless ($target eq $root) {
		my ($parent, $me) = ($target =~ m/^(.+)::([^:]+)$/);
		if ($_opts{inherit}) {
			# class inherits parent's topic
			$topic = $INFO{$root}->{_topics}->{$parent};
		} else {
			$topic = '/'.lc($me);
			$topic = $INFO{$root}->{_topics}->{$parent}.'/'.lc($me)
				unless $parent eq $root;
		}
	}

	$INFO{$root}->{_topics}->{$target} = $topic;

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
	foreach my $meth ( [qw/get GET/], [qw/put PUT/], [qw/post POST/], [qw/del DELETE/] ) {
		*{$target.'::'.$meth->[0]} = sub { &{"${target}::provide"}($meth->[1], @_) };
	}

	if ($target eq $root && $INFO{$root}->{_opts} && $INFO{$root}->{_opts}->{contextual}) {
		# we're running in contextual mode, which means the API
		# should have a Context class called $root::Context.
		# when call() is, umm, called, we need to create a new instance
		# of the context class and pass it to the route as well.
		# we expect this class to be called $root::Context, but if it
		# does not exist, we will try going up the hierarchy until we
		# find one.
		my $ctx;
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

		$INFO{$root}->{_opts}->{context_class} = $ctx
			|| croak "No context class found";
	}

	# export the pre_route and post_route "constructors"
	foreach my $mod (qw/pre_route post_route/) {
		*{$target.'::'.$mod} = sub (&) {
			$INFO{$root}->{"_$mod"} ||= {};
			$INFO{$root}->{"_$mod"}->{$topic} = shift;
		};
	}

	# we're done with exporting, now lets try to load all
	# child topics (if any)
	# << this code is based on code from Module::Find >>
	foreach my $inc_dir (grep { -d $_ } map { File::Spec->catdir($_, split(/::/, $target)) } @INC) {
		opendir DIR, $inc_dir;
		my @pms = grep { !-d && m/\.pm$/ && !($INFO{$root}->{_opts} && $INFO{$root}->{_opts}->{contextual} && $_ eq 'Context.pm') } readdir DIR;
		closedir DIR;

		foreach (@pms) {
			require File::Spec->catdir($inc_dir, $_);
		}
	}
}

# _find_root( $current_class )
# -- finds the root topic of the API, which might
#    very well be the module we're currently importing into

sub _find_root {
	$_ = $_[0];
	while (s/::.+$//) {
		$INFO{$_} && return $_;
	}
	$_[0];
}

1;
__END__
