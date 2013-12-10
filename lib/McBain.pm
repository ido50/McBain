package McBain;

# ABSTRACT: Framework for building portable, auto-validating and self-documenting APIs

BEGIN {
	$ENV{MCBAIN_WITH} ||= 'Directly';
};

use parent "McBain::$ENV{MCBAIN_WITH}";
use warnings;
use strict;

use Brannigan;
use Carp;
use File::Spec;
use Scalar::Util qw/blessed/;
use Try::Tiny;

our $VERSION = "1.000000";
$VERSION = eval $VERSION;

=head1 NAME
 
McBain - Framework for building portable, auto-validating and self-documenting APIs

=head1 SYNOPSIS

	package MyAPI;

	use McBain; # imports strict and warnings for you

	get '/add' => (
		description => 'Adds two integers',
		params => {
			one => { required => 1, integer => 1 },
			two => { required => 1, integer => 1 }
		},
		cb => sub {
			my ($api, $params) = @_;

			return $params->{one} + $params->{two};
		}
	);

	1;

=head1 DESCRIPTION

C<McBain> is a framework for building powerful APIs and applications. Writing an API with C<McBain> provides the following benefits:

=over

=item * B<Lightweight-ness>

C<McBain> is extremely lightweight, with minimal dependencies on non-core modules; only two packages; and a succinct, minimal syntax that is easy to remember. Your APIs and applications will require less resources and perform better. Maybe.

=item * B<Portability>

C<McBain> APIs can be run/used in a variety of ways with absolutely no changes of code. For example, they can be used B<directly from Perl code> (see L<McBain::Directly>), as fully fledged B<RESTful PSGI web services> (see L<McBain::WithPSGI>), or as B<Gearman workers> (see L<McBain::WithGearmanXS>). Seriously, no change of code required. More C<McBain> runners are yet to come, and you can create your own, god knows I don't have the time or motivation or talent. Why should I do it for you anyway?

=item * B<Auto-Validation>

No more tedious input tests. C<McBain> will handle input validation for you. All you need to do is define the parameters you expect to get with the simple and easy to remember syntax provided by L<Brannigan>. When your API is used, C<McBain> will automatically validate input. If validation fails, C<McBain> will return appropriate errors and tell the users of your API that they suck.

=item * B<Self-Documentation>

C<McBain> also eases the burden of having to document your APIs, so that other people can actually use it (and you, two weeks later when you're drunk and can't remember why you wrote the thing in the first place). Using simple descriptions you give to your API's methods, and the parameter definitions, C<McBain> can automatically create a manual document describing your API (see the L<mcbain2pod> command line utility).

=item * B<Modularity and Flexibility>

APIs written with C<McBain> are modular and flexible. You can make them object oriented if you want, or not, C<McBain> won't care, it's unobtrusive like that. APIs are hierarchical, and every module in the API can be used as a complete API all by itself, detached from its siblings, so you can actually load only the parts of the API you need. Why is this useful? I don't know, maybe it isn't, what do I care? It happened by accident anyway.

=item * B<No More World Hunger>

It'll do that too, just give it a chance.

=back

=cut

our %INFO;

sub import {
	my $target = caller;
	return if $target eq 'main';
	my $me = shift;
	strict->import;
	warnings->import(FATAL => 'all');
	return if $INFO{$target};

	# find the root of this API (if it's not this class)
	my $root = _find_root($target);

	# create the routes hash for $root
	$INFO{$root} ||= {};

	# figure out the topic name from this class
	my $topic = '/';
	unless ($target eq $root) {
		my ($rel_name) = ($target =~ m/^${root}::(.+)$/)[0];
		$topic = '/'.lc($rel_name);
		$topic =~ s!::!/!g;
	}

	no strict 'refs';

	*{"${target}::is_root"} = sub {
		exists $INFO{$target};
	};

	__PACKAGE__->init($target);

	*{"${target}::provide"} = sub {
		my ($method, $name) = (shift, shift);
		my %opts = @_;

		$name = '/'.$name
			unless $name =~ m{^/};
		$name .= '/'
			unless $name =~ m{/$};
		$name = $topic.$name
			unless $topic eq '/';

		$INFO{$root}->{$name} ||= {};
		$INFO{$root}->{$name}->{$method} = \%opts;
	};

	foreach my $meth (
		[qw/get GET/],
		[qw/put PUT/],
		[qw/post POST/],
		[qw/del DELETE/]
	) {
		*{$target.'::'.$meth->[0]} = sub {
			&{"${target}::provide"}($meth->[1], @_);
		};
	}

	*{"${target}::call"} = sub {
		my ($self, @args) = @_;
		return try {
			my $env = __PACKAGE__->generate_env(@args);
			my $res = $self->forward($env->{METHOD}.':'.$env->{NAMESPACE}, $env->{PAYLOAD});
			return __PACKAGE__->generate_res($env, $res);
		} catch {
			return __PACKAGE__->handle_exception($_, @args);
		};
	};

	*{"${target}::forward"} = sub {
		my ($self, $meth_and_route, $payload) = @_;

		my ($meth, $route) = split(/:/, $meth_and_route);

		$route .= '/'
			unless $route =~ m{/$};

		# find this route
		my $r = $INFO{$root}->{$route}
			|| confess { code => 404, error => "Route $route does not exist" };

		# does this route have the HTTP method?
		confess { code => 405, error => "Method $meth not available for route $route" }
			unless exists $r->{$meth};

		# process parameters
		my $params_ret = Brannigan::process({ params => $r->{$meth}->{params} }, $payload);

		confess { code => 400, error => "Parameters failed validation", rejects => $params_ret->{_rejects} }
			if $params_ret->{_rejects};

		return $r->{$meth}->{cb}->($self, $params_ret);
	};

	_load_topics($target);
}

sub _find_root {
	my $class = shift;

	if ($class =~ m/::[^:]+$/) {
		# we have a parent, and it might
		# be the root. otherwise the root
		# is us
		my $parent = _find_root($`);
		return $parent || $class;
	} else {
		# we don't have a parent, so we are the root
		return $class;
	}
}

sub _load_topics {
	my ($base, $limit) = @_;

	# this code is based on code from Module::Find

	my $pkg_dir = File::Spec->catdir(split(/::/, $base));

	my @inc_dirs = map { File::Spec->catdir($_, $pkg_dir) } @INC;

	foreach my $inc_dir (@inc_dirs) {
		next unless -d $inc_dir;

		opendir DIR, $inc_dir;
		my @pms = grep { !-d && m/\.pm$/ } readdir DIR;
		closedir DIR;

		foreach my $file (@pms) {
			my $pkg = $file;
			$pkg =~ s/\.pm$//;
			$pkg = join('::', File::Spec->splitdir($pkg));

			require File::Spec->catdir($inc_dir, $file);
		}
	}
}

=head1 CONFIGURATION AND ENVIRONMENT
   
C<McBain> itself requires no configuration files or environment variables.
However, when using/running APIs written with C<McBain>, the C<MCBAIN_WITH>
environment variable might be needed to tell C<McBain> the name of the
runner module to use. The default value is "Directly", so L<McBain::Directly>
is used. See the various C<McBain> runner modules for more information.
 
=head1 DEPENDENCIES
 
C<McBain> depends on the following CPAN modules:
 
=over
 
=item * L<Brannigan>
 
=item * L<Carp>

=item * L<File::Spec>

=item * L<Scalar::Util>
 
=item * L<Try::Tiny>
 
=back
 
The command line utility, L<mcbain2pod>, depends on the following CPAN modules:
 
=over

=item * L<IO::Handle>

=item * L<Getopt::Compact>

=item * L<Module::Load>

=back

=head1 INCOMPATIBILITIES WITH OTHER MODULES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-McBain@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=McBain>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc McBain

You can also look for information at:

=over 4
 
=item * RT: CPAN's request tracker
 
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=McBain>
 
=item * AnnoCPAN: Annotated CPAN documentation
 
L<http://annocpan.org/dist/McBain>
 
=item * CPAN Ratings
 
L<http://cpanratings.perl.org/d/McBain>
 
=item * Search CPAN
 
L<http://search.cpan.org/dist/McBain/>
 
=back
 
=head1 AUTHOR
 
Ido Perlmuter <ido@ido50.net>
 
=head1 LICENSE AND COPYRIGHT
 
Copyright (c) 2013, Ido Perlmuter C<< ido@ido50.net >>.
 
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself, either version
5.8.1 or any later version. See L<perlartistic|perlartistic>
and L<perlgpl|perlgpl>.
 
The full text of the license can be found in the
LICENSE file included with this module.
 
=head1 DISCLAIMER OF WARRANTY
 
BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.
 
IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
 
=cut

1;
__END__
