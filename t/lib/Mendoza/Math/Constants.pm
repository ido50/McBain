package Mendoza::Math::Constants;

use McBain;

get '/' => (
	description => 'Returns something from the parent and something from the root',
	cb => sub {
		return $_[0]->status.', AND '.$_[0]->message;
	}
);

get '/pi' => (
	cb => sub {
		return 3.14159265359;
	}
);

get '/(golden_ratio|euler\'s_number)' => (
	cb => sub {
		my ($self, $params, $constant) = @_;

		if ($constant eq 'golden_ratio') {
			return 1.61803398874;
		} else {
			return 2.71828;
		}
	}
);

1;
__END__
