package McBain::WithGearmanXS;

use warnings;
use strict;

use Carp;
use Gearman::XS qw(:constants);
use Gearman::XS::Worker;
use JSON;

sub init {
	my ($class, $target) = @_;

	if ($target->is_root) {
		no strict 'refs';
		*{"${target}::work"} = sub {
			my ($pkg, $host, $port) = @_;

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
}

sub register_functions {
	my ($class, $worker, $target, $topic) = @_;

	foreach my $meth_name (keys %{$topic->{methods}}) {
		my $meth = $topic->{methods}->{$meth_name};
		foreach my $http_meth (keys %$meth) {
			my $namespace = $http_meth.':'.$topic->{topic}.$meth_name;
			$namespace =~ s{/+}{/}g;
			unless (
				$worker->add_function($namespace, 0, sub {
					$target->call($_[0]);
				}, {}) == GEARMAN_SUCCESS
			) {
				croak "Can't register function $namespace, ".$worker->error;
			}
		}
	}

	foreach my $subtopic (keys %{$topic->{topics}}) {
		$class->register_functions($worker, $target, $topic->{topics}->{$subtopic});
	}
}

sub generate_env {
	my ($self, $job) = @_;

	croak "400 Bad Request"
		unless $job->function_name =~ m/^(GET|POST|PUT|DELETE):/;

	my ($method, $namespace) = split(/:/, $job->function_name);

	return {
		METHOD    => $method,
		NAMESPACE => $namespace,
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
