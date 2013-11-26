#!/usr/bin/perl -w

BEGIN { $ENV{MCBAIN_WITH} = 'WithGearmanXS'; }

use lib 'lib', 't/lib';
use warnings;
use strict;
use Mendoza;

my $app = Mendoza->new;

$app->work('localhost', 4730);
