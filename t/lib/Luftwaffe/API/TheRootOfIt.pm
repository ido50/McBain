package Luftwaffe::API::TheRootOfIt;

use McBain::Mo;
use McBain -contextual;

get '/' => (
	cb => sub {
		return ref $_[1];
	}
);

get '/forward' => (
	cb => sub {
		$_[1]->forward('GET:/')
	}
);

1;
__END__
