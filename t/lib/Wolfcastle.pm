package Wolfcastle;

use McBain::Mo;
use McBain -contextual;

get '/' => (
	description => 'Returns the name of the API',
	cb => sub {
		return 'MEN-DO-ZAAAAAAAAAAAAA!!!!!!!!!!!';
	}
);

get '/status' => (
	description => 'Returns the status of the API',
	cb => sub { $_[1]->status }
);

1;
__END__
