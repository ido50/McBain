package Greta;

use Carp;

use McBain::Mo;
use McBain -contextual;

get '/' => (
	cb => sub {
		return "d'oh";
	}
);

1;
__END__
