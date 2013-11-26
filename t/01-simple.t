#!/usr/bin/perl -w

use lib 't/lib';
use warnings;
use strict;

use Mendoza;
use Test::More;
use Test::Exception;

my $api = Mendoza->new;

is($api->call('/status'), 'ALL IS WELL', 'status ok');
is($api->call('/math/sum', { one => 1, two => 2 }), 3, 'sum ok');
is($api->call('/math/diff', { one => 3, two => 1 }), 2, 'diff ok');
is($api->call('/math/factorial', { num => 5 }), 120, 'factorial ok');
dies_ok { $api->call('/math/sum', { one => 'a', two => 2 }) } 'bad param ok';
dies_ok { $api->call('/math/asdf', { one => 1, two => 2 }) } 'wrong method ok';
dies_ok { $api->call('/nath/sum', { one => 1, two => 2 }) } 'wrong topic ok';

done_testing();
