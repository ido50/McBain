package Mendoza::Math::Inherits::Too;

use McBain::Mo;
use McBain -inherit;

get '/stiller' => (
	cb => sub {
		return 'Ben Stiller';
	}
);

1;
__END__
