package Wolfcastle;

use McBain -contextual;

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

sub new { bless { status => 'ALL IS WELL' }, shift };

sub status { shift->{status} }

sub create_context { Wolfcastle::Context->new($_[1]) }

1;
__END__
