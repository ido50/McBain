package Mendoza::Math::Inherits;

use McBain::Mo;
use McBain -inherit;

get '/dodgeball' => (
	cb => sub {
		return 'Dodgeball';
	}
);

1;
__END__
