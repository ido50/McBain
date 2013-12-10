package Mendoza;

use Moo;
use McBain;

has 'status' => (is => 'ro', default => 'ALL IS WELL');

get '/' => (
	description => 'Returns the name of the API',
	cb => sub {
		return 'MEN-DO-ZAAAAAAAAAAAAA!!!!!!!!!!!';
	}
);

get '/status' => (
	description => 'Returns the status of the API',
	cb => sub {
		use Data::Dumper; print STDERR Dumper(\@_);
		return shift->status;
	}
);

1;
__END__
