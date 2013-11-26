package McBain::WithGearmanXS;

use warnings;
use strict;

use Carp;
use Gearman::XS qw(:constants);
use Gearman::XS::Worker;
use JSON;

sub init {
	my ($class, $target) = @_;

	no strict 'refs';

	*{"${target}::work"} = sub {
		my ($pkg, $host, $port) = @_;

		return unless $target->_find_root eq $target;

		$host ||= 'localhost';
		$port ||= 4730;

		my $worker = Gearman::XS::Worker->new;
		unless ($worker->add_server($host, $port) == GEARMAN_SUCCESS) {
			croak "Can't connect to gearman server at $host:$port, ".$worker->error;
		}

		$class->register_functions($worker, $target, $McBain::INFO{$target});

		while (1) {
			$worker->work();
		}
	};
}

sub register_functions {
	my ($class, $worker, $target, $topic) = @_;

	foreach my $meth (keys %{$topic->{methods}}) {
		my $namespace = $topic->{topic}.$meth;
		$namespace =~ s{/+}{/}g;
		unless (
			$worker->add_function($namespace, 0, sub {
				$target->call($_[0]);
			}, {}) == GEARMAN_SUCCESS) {
				croak "Can't register function $topic->{topic}$meth, ".$worker->error;
			}
	}

	foreach my $subtopic (keys %{$topic->{topics}}) {
		$class->register_functions($worker, $target, $topic->{topics}->{$subtopic});
	}
}

sub generate_env {
	my ($self, $job) = @_;

	return {
		METHOD    => 'GET',
		NAMESPACE => $job->function_name,
		PAYLOAD   => $job->workload ? decode_json($job->workload) : {}
	};
}

sub generate_res {
	my ($self, $env, $res) = @_;

	$res = { $env->{NAMESPACE} => $res }
		unless ref $res eq 'HASH';

	return encode_json($res);
}

1;
