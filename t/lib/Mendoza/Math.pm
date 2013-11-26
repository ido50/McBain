package Mendoza::Math;

use McBain;

get sum => (
	description => 'Adds two integers',
	params => {
		one => { required => 1, integer => 1 },
		two => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params) = @_;

		return $params->{one} + $params->{two};
	}
);

get diff => (
	description => 'Subtracts two integers',
	params => {
		one => { required => 1, integer => 1 },
		two => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params) = @_;

		return $params->{one} - $params->{two};
	}
);

get mult => (
	description => 'Multiplies two integers',
	params => {
		one => { required => 1, integer => 1 },
		two => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params) = @_;

		return $params->{one} * $params->{two};
	}
);

get factorial => (
	description => 'Returns the factorial of a number',
	params => {
		num => { required => 1, integer => 1 }
	},
	cb => sub {
		my ($api, $params) = @_;

		return $params->{num} <= 1 ? 1 : $api->forward('/math/mult', {
			one => $params->{num},
			two => $api->forward('/math/factorial', { num => $params->{num} - 1 })
		});
	}
);

1;
__END__