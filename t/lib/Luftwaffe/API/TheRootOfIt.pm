package Luftwaffe::API::TheRootOfIt;

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

sub new { bless {}, shift };

1;
__END__
