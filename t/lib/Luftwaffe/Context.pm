package Luftwaffe::Context;

use Moo;

extends 'McBain::Context';

has 'params' => (is => 'rw', default => sub { {} });

has 'path' => (is => 'rw');

has 'method' => (is => 'rw');

sub process_env {
	my ($self, $env) = @_;

	$self->params($env->{PAYLOAD});
	$self->path($env->{ROUTE});
	$self->method($env->{METHOD});
}

1;
__END__
