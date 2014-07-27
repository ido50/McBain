package Wolfcastle::Math;

use McBain -contextual;

get '/sum' => (
	description => 'Adds two integers from params',
	params => {
		one => { required => 1, integer => 1 },
		two => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params, $c) = @_;

		return $params->{one} + $params->{two};
	}
);

get '/diff' => (
	description => 'Subtracts two integers',
	params => {
		one => { required => 1, integer => 1 },
		two => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params, $c) = @_;

		if ($c->user->{name} eq 'ido') {
			return 5;
		}

		return $params->{one} - $params->{two};
	}
);

get '/mult' => (
	description => 'Multiplies two integers',
	params => {
		one => { required => 1, integer => 1 },
		two => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params, $c) = @_;

		return $params->{one} * $params->{two};
	}
);

post '/factorial' => (
	description => 'Returns the factorial of a number',
	params => {
		num => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params, $c) = @_;

		return $params->{num} <= 1 ? 1 : $api->forward('GET:/math/mult', {
			one => $params->{num},
			two => $api->forward('POST:/math/factorial', { num => $params->{num} - 1 })
		});
	}
);

1;
__END__
