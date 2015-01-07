package Luftwaffe::Context;

use Moo;

has 'params' => (is => 'rw', default => sub { {} });

has 'path' => (is => 'rw');

has 'method' => (is => 'rw');

has 'topic' => (is => 'rw');

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
