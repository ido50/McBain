package McBain;

# ABSTRACT: Framework for building auto-validating, self-documenting APIs

BEGIN {
	$ENV{MCBAIN_WITH} ||= 'Directly';
};

use lib './lib';
use parent "McBain::$ENV{MCBAIN_WITH}";
use warnings;
use strict;

use Brannigan;
use Carp;
use File::Spec;
use Scalar::Util qw/blessed/;

our $VERSION = "1.000000";
$VERSION = eval $VERSION;

our %INFO;

sub import {
	my $target = caller;
	return if $target eq 'main';
	my $me = shift;
	strict->import;
	warnings->import(FATAL => 'all');
	return if $INFO{$target};

	# find the root of this API (if it's not this class)
	my $root = _find_root($target);

	# create the routes hash for $root
	$INFO{$root} ||= {};

	# figure out the topic name from this class
	my $topic = '/';
	unless ($target eq $root) {
		my ($rel_name) = ($target =~ m/^${root}::(.+)$/)[0];
		$topic = '/'.lc($rel_name);
		$topic =~ s!::!/!g;
	}

	no strict 'refs';

	*{"${target}::is_root"} = sub {
		exists $INFO{$target};
	};

	__PACKAGE__->init($target);

	*{"${target}::provide"} = sub {
		my ($method, $name) = (shift, shift);
		my %opts = @_;

		$name = '/'.$name
			unless $name =~ m{^/};
		$name .= '/'
			unless $name =~ m{/$};
		$name = $topic.$name
			unless $topic eq '/';

		$INFO{$root}->{$name} ||= {};
		$INFO{$root}->{$name}->{$method} = \%opts;
	};

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

	*{"${target}::call"} = sub {
		my $self = shift;
		my $env = __PACKAGE__->generate_env(@_);
		my $res = $self->forward($env->{METHOD}.':'.$env->{NAMESPACE}, $env->{PAYLOAD});
		return __PACKAGE__->generate_res($env, $res);
	};

	*{"${target}::forward"} = sub {
		my ($self, $meth_and_route, $payload) = @_;

		croak "400 Bad Request"
			unless $meth_and_route =~ m/^[^:]+:[^:]+$/;

		my ($meth, $route) = split(/:/, $meth_and_route);

		$route .= '/'
			unless $route =~ m{/$};

		#print STDERR "Trying to find $meth $route\n========================\n";
		#use Data::Dumper; print STDERR join("\n", keys %{$INFO{$root}}), "\n";

		# find this route
		my $r = $INFO{$root}->{$route}
			|| croak "404 Not Found";

		# does this route have the HTTP method?
		croak "405 Method Not Allowed"
			unless exists $r->{$meth};

		# process parameters
		my $params_ret = Brannigan::process({ params => $r->{$meth}->{params} }, $payload);

		croak "Parameters failed validation"
			if $params_ret->{_rejects};

		return $r->{$meth}->{cb}->($self, $params_ret);
	};

	_load_topics($target);
}

sub _find_root {
	my $class = shift;

	if ($class =~ m/::[^:]+$/) {
		# we have a parent, and it might
		# be the root. otherwise the root
		# is us
		my $parent = _find_root($`);
		return $parent || $class;
	} else {
		# we don't have a parent, so we are the root
		return $class;
	}
}

sub _load_topics {
	my ($base, $limit) = @_;

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

			require File::Spec->catdir($inc_dir, $file);
		}
	}
}

1;
__END__
