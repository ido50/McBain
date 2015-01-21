package Mendoza;

use Carp;

use Moo;
use McBain;

has 'status' => (
	is => 'ro',
	default => sub { 'ALL IS WELL' }
);

get '/' => (
	description => 'Returns the name of the API',
	cb => sub {
		return 'MEN-DO-ZAAAAAAAAAAAAA!!!!!!!!!!!';
	}
);

get '/status' => (
	description => 'Returns the status of the API',
	cb => sub { shift->status }
);

get '/(pre|post)_route_test' => (
	cb => sub { 'asdf' }
);

pre_route {
	my ($self, $ns, $params) = @_;

	croak { code => 500, error => "pre_route doesn't like you" }
		if $ns eq 'GET:/pre_route_test/';
};

post_route {
	my ($self, $ns, $result) = @_;

	$$result = 'post_route messed you up'
		if $ns eq 'GET:/post_route_test/';
};

1;
__END__
