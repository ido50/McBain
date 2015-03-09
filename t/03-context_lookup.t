#!/usr/bin/perl -w

use lib 't/lib';
use warnings;
use strict;

use Luftwaffe::API::TheRootOfIt;
use Test::More tests => 2;
use Data::Dumper;
use Try::Tiny;

try {
	my $api = Luftwaffe::API::TheRootOfIt->new;

	is($api->call('GET:/'), 'Luftwaffe::Context', 'Non-root context class found');
	is($api->call('GET:/forward'), 'Luftwaffe::Context', 'Forward implemented correctly');
} catch {
	diag(Dumper($_));
};

done_testing();
