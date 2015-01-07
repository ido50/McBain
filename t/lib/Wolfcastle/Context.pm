package Wolfcastle::Context;

use Moo;

extends 'McBain::Context';

has 'params' => (is => 'rw', default => sub { {} });

has 'path' => (is => 'rw');

has 'method' => (is => 'rw');

has 'user' => (is => 'ro', default => sub { { name => 'ido', email => 'my@email.com' } });

sub process_env {
	my ($self, $env) = @_;

	$self->params($env->{PAYLOAD});
	$self->path($env->{ROUTE});
	$self->method($env->{METHOD});
}

sub status { 'ALL IS WELL' }

1;
__END__
