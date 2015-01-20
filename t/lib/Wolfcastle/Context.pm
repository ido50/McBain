package Wolfcastle::Context;

use McBain::Mo;

has 'params';

has 'path';

has 'method';

has 'user';

sub process_env {
	my ($self, $env) = @_;

	$self->params($env->{PAYLOAD});
	$self->path($env->{ROUTE});
	$self->method($env->{METHOD});
	$self->user({ name => 'ido', email => 'my@email.com' });
}

sub status { 'ALL IS WELL' }

1;
__END__
