package Luftwaffe::Context;

use McBain::Mo;

has 'params';

has 'path';

has 'method';

has 'topic';

sub process_env {
	my ($self, $topic, $env) = @_;

	$self->params($env->{PAYLOAD});
	$self->path($env->{ROUTE});
	$self->method($env->{METHOD});

	$self->topic($topic);
}

sub forward {
	my $self = shift;

	$self->topic->call(@_);
}

1;
__END__
