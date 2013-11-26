#!/usr/bin/perl -w

BEGIN { $ENV{MCBAIN_WITH} = 'WithPSGI'; }

use lib 'lib', 't/lib';
use warnings;
use strict;
use Mendoza;

my $app = Mendoza->new->to_app;
