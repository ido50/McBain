#!/usr/bin/perl -w

use lib 't/lib';
use warnings;
use strict;

use Test::More tests => 1;
use Test::Exception;
use Data::Dumper;
use Try::Tiny;

eval "require Greta";
ok($@ && $@ =~ m/Compilation failed in require/, 'syntax error in context class causes detailed confession');

done_testing();
