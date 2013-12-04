package Mendoza::Math::Constants;

use McBain;

get '/' => (
	cb => sub {
		return "I CAN HAZ CONSTANTS";
	}
);

get '/pi' => (
	cb => sub {
		return 3.14159265359;
	}
);

1;
__END__
