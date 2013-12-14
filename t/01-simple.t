#!/usr/bin/perl -w

use lib 't/lib';
use warnings;
use strict;

use Mendoza;
use Test::More tests => 16;
use Test::Exception;

my $api = Mendoza->new;

is($api->call('GET:/status'), 'ALL IS WELL', 'status ok');
is($api->call('GET:/math'), 'MATH IS AWESOME', 'math ok #1');
is($api->call('GET:/math/'), 'MATH IS AWESOME', 'math ok #2');
is($api->call('GET:/math/sum', { one => 1, two => 2 }), 3, 'sum from params ok');
is($api->call('GET:/math/sum/1/2'), 3, 'sum from path ok');
is($api->call('GET:/math/diff', { one => 3, two => 1 }), 2, 'diff ok');
dies_ok { $api->call('GET:/math/factorial', { num => 5 }) } 'factorial dies ok when bad method';
is($api->call('POST:/math/factorial', { num => 0 }), 1, 'factorial zero ok');
is($api->call('POST:/math/factorial', { num => 5 }), 120, 'factorial non-zero ok');
is($api->call('GET:/math/constants'), 'I CAN HAZ CONSTANTS', 'constants ok');
is($api->call('GET:/math/constants/pi'), 3.14159265359, 'pi ok');
is($api->call('GET:/math/constants/golden_ratio'), 1.61803398874, 'golden ratio ok');
dies_ok { $api->call('GET:/math/constants/golden_ration') } 'bad regex ok';
dies_ok { $api->call('GET:/math/sum', { one => 'a', two => 2 }) } 'bad param ok';
dies_ok { $api->call('GET:/math/asdf', { one => 1, two => 2 }) } 'wrong method ok';
dies_ok { $api->call('GET:/nath/sum', { one => 1, two => 2 }) } 'wrong topic ok';

done_testing();
