package McBain;

# ABSTRACT: Framework for building auto-validating, self-documenting APIs

BEGIN {
	$ENV{MCBAIN_WITH} ||= 'Directly';
};

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

	__PACKAGE__->init($target);

	$INFO{$target} = {
		topic => '/', # only the root topic will have this as slash
		methods => {},
		topics => {}
	};

	no strict 'refs';

	*{"${target}::provide"} = sub {
		my $name = shift;
		my %opts = @_;

		$name = '/'.$name
			unless $name =~ m{^/};

		$INFO{$target}->{methods} ||= {};
		$INFO{$target}->{methods}->{$name} = \%opts;
	};

	foreach my $meth (
		[qw/get GET/],
		[qw/put PUT/],
		[qw/post POST/],
		[qw/del DELETE/]
	) {
		*{$target.'::'.$meth->[0]} = sub {
			my $name = shift;
			my %opts = @_;
			$opts{method} = $meth->[1];
			&{"${target}::provide"}($name, %opts);
		};
	}

	*{"${target}::call"} = sub {
		my $self = shift;
		my $env = __PACKAGE__->generate_env(@_);
		my $res = $self->forward($env->{NAMESPACE}, $env->{PAYLOAD});
		return __PACKAGE__->generate_res($env, $res);
	};

	*{"${target}::forward"} = sub {
		my ($self, $namespace, $payload) = @_;

		my $class = blessed $self || $self;

		# $namespace is the full name of the method, i.e. /<topic>/<method>
		# extract the names of the topic and the method itself from it
		my $ns = $namespace;
		$ns =~ s{^/}{}; # remove starting slash
		my ($tn, $mn) = split(/\//, $ns); # topic name, method name
		if (!$mn) {
			# this topic
			$mn = $tn ? "/$tn" : '/';
			$tn = '/';
		} elsif ($namespace =~ m{/([^/]+)$}) {
			# child topic
			$tn = $`;
			$mn = "/$1";
		} else {
			croak "Illegal namespace $namespace";
		}

		# now find the topic
		my $topic;
		if ($tn eq '/') {
			# it's this topic
			$topic = $INFO{$class};
		} else {
			# it's a subtopic
			$topic = _find_subtopic($class, $tn)
				|| croak "404 Not Found";
		}

		# and now find the method
		unless (exists $topic->{methods}->{$mn}) {
			# maybe we're calling the root of a subtopic
			$tn = $tn eq '/' ? $mn : $tn.$mn;
			$mn  = '/';

			$topic = _find_subtopic($class, $tn)
				|| croak "404 Not Found";
		}

		my $method = $topic->{methods}->{$mn}
			|| croak "404 Not Found";

		# process parameters
		my $params_ret = Brannigan::process({ params => $method->{params} }, $payload);

		croak "Parameters failed validation"
			if $params_ret->{_rejects};

		return $method->{cb}->($self, $params_ret);
	};

	my %topics = _load_topics($target);
	foreach my $pkg (keys %topics) {
		my $file  = $topics{$pkg}->{file};
		my $topic = '/'.$topics{$pkg}->{topic};

		# require the package
		require $file;

		$INFO{$pkg}->{topic} = $topic;

		# add package to parent's topics hash (parent == target)
		$INFO{$target}->{topics}->{$topic} = $INFO{$pkg};
	}
}

sub _load_topics {
	my ($base, $limit) = @_;

	# this code is based on code from Module::Find

	my $pkg_dir = File::Spec->catdir(split(/::/, $base));

	my @inc_dirs = map { File::Spec->catdir($_, $pkg_dir) } @INC;

	my %topics;

	foreach my $inc_dir (@inc_dirs) {
		next unless -d $inc_dir;

		opendir DIR, $inc_dir;
		my @pms = grep { !-d && m/\.pm$/ } readdir DIR;
		closedir DIR;

		foreach my $file (@pms) {
			my $pkg = $file; $pkg =~ s/\.pm$//; $pkg = join('::', File::Spec->splitdir($pkg));
			my $topic = lc($pkg); $topic =~ s/::/./g;

			$topics{$base.'::'.$pkg} = {
				file => File::Spec->catdir($inc_dir, $file),
				topic => $topic
			};
		}
	}

	return %topics;
}

sub _find_subtopic {
	my ($class, $tn) = @_;

	my @chain = split(/\//, $tn);
	shift @chain; # since $tn begins with / first item will be empty

	my $root = $INFO{$class};

	while (scalar @chain) {
		my $next = '/'.shift(@chain);
		$root = $root->{topics}->{$next}
			|| return;
	}

	return $root;
}

1;
__END__
