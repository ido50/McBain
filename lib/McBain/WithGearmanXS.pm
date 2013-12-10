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
				confess "Can't connect to gearman server at $host:$port, ".$worker->error;
			}

			$class->register_functions($worker, $pkg, $McBain::INFO{$target});

			while (1) {
				$worker->work();
			}
		};
	}
}

sub register_functions {
	my ($class, $worker, $target, $topic) = @_;

	foreach my $route (keys %$topic) {
		foreach my $meth (keys %{$topic->{$route}}) {
			my $namespace = $meth.':'.$route;
			$namespace =~ s!/$!!
				unless $route eq '/';
			unless (
				$worker->add_function($namespace, 0, sub {
					$target->call($_[0]);
				}, {}) == GEARMAN_SUCCESS
			) {
				confess "Can't register function $namespace, ".$worker->error;
			}
		}
	}
}

sub generate_env {
	my ($self, $job) = @_;

	confess { code => 400, error => "Namespace must match <METHOD>:<ROUTE> where METHOD is one of GET, POST, PUT or DELETE" }
		unless $job->function_name =~ m/^(GET|POST|PUT|DELETE):[^:]+$/;

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

sub handle_exception {
	my ($class, $err, $job) = @_;

	$job->send_fail;
}

1;
