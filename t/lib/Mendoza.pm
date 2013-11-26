package Mendoza;

use Moo;
use McBain;

get '' => (
	description => 'Returns the name of the API',
	cb => sub {
		return 'MEN-DO-ZAAAAAAAAAAAAA!!!!!!!!!!!';
	}
);

get status => (
	description => 'Returns the status of the API',
	cb => sub {
		return 'ALL IS WELL';
	}
);

1;
__END__
