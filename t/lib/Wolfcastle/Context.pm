package Wolfcastle::Context;

use warnings;
use strict;

sub new {
	my ($class, $env) = @_;

	bless {
		params => $env->{PAYLOAD},
		path => $env->{ROUTE},
		method => $env->{METHOD},
		user => {
			name => 'ido',
			email => 'my@email.com'
		}
	}, $class;
}

sub params { shift->{params} || {} }

sub path { shift->{path} }

sub method { shift->{method} }

sub user { shift->{user} }

1;
__END__
