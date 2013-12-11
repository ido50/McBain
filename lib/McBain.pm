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

	get '/multiply' => (
		description => 'Multiplies two integers',
		params => {
			one => { required => 1, integer => 1 },
			two => { required => 1, integer => 1 }
		},
		cb => sub {
			my ($api, $params) = @_;

			return $params->{one} + $params->{two};
		}
	);

	post '/factorial' => (
		description => 'Calculates the factorial of an integer',
		params => {
			num => { required => 1, integer => 1, min_value => 0 }
		},
		cb => sub {
			my ($api, $params) = @_;

			# note how this route both uses another
			# route and calls itself recursively

			if ($params->{num} <= 1) {
				return 1;
			} else {
				return $api->forward('GET:/multiply', {
					one => $params->{num},
					two => $api->forward('POST:/factorial', { num => $params->{num} - 1 })
				});
			}
		}
	);

	1;

=head1 DESCRIPTION

C<McBain> is a framework for building powerful APIs and applications. Writing an API with C<McBain> provides the following benefits:

=over

=item * B<Lightweight-ness>

C<McBain> is extremely lightweight, with minimal dependencies on non-core modules; only two packages; and a succinct, minimal syntax that is easy to remember. Your APIs and applications will require less resources and perform better. Maybe.

=item * B<Portability>

C<McBain> APIs can be run/used in a variety of ways with absolutely no changes of code. For example, they can be used B<directly from Perl code> (see L<McBain::Directly>), as fully fledged B<RESTful PSGI web services> (see L<McBain::WithPSGI>), or as B<Gearman workers> (see L<McBain::WithGearmanXS>). Seriously, no change of code required. More L<McBain runners|"MCBAIN RUNNERS"> are yet to come, and you can create your own, god knows I don't have the time or motivation or talent. Why should I do it for you anyway?

=item * B<Auto-Validation>

No more tedious input tests. C<McBain> will handle input validation for you. All you need to do is define the parameters you expect to get with the simple and easy to remember syntax provided by L<Brannigan>. When your API is used, C<McBain> will automatically validate input. If validation fails, C<McBain> will return appropriate errors and tell the users of your API that they suck.

=item * B<Self-Documentation>

C<McBain> also eases the burden of having to document your APIs, so that other people can actually use it (and you, two weeks later when you're drunk and can't remember why you wrote the thing in the first place). Using simple descriptions you give to your API's methods, and the parameter definitions, C<McBain> can automatically create a manual document describing your API (see the L<mcbain2pod> command line utility).

=item * B<Modularity and Flexibility>

APIs written with C<McBain> are modular and flexible. You can make them object oriented if you want, or not, C<McBain> won't care, it's unobtrusive like that. APIs are hierarchical, and every module in the API can be used as a complete API all by itself, detached from its siblings, so you can actually load only the parts of the API you need. Why is this useful? I don't know, maybe it isn't, what do I care? It happened by accident anyway.

=item * B<No More World Hunger>

It'll do that too, just give it a chance.

=back

=head1 FUNCTIONS

The following functions are exported:

=head2 provide( $method, $route, %opts )

Define a method and a route. C<$method> is one of C<GET>, C<POST>, C<PUT>
or C<DELETE>. C<$route> is a string that starts with a forward slash,
like a path in a URI. C<%opts> can hold the following keys (only C<cb>
is required):

=over

=item * description

A short description of the method and what it does.

=item * params

A hash-ref of parameters in the syntax of L<Brannigan> (see L<Brannigan::Validations>
for a complete references).

=item * cb

An anonymous subroutine (or a subroutine reference) to run when the route is
called. The method will receive the root topic class (or object, if the
topics are written in object oriented style), and a hash-ref of parameters.

=back

=head2 get( $route, %opts )

Shortcut for C<provide( 'GET', $route, %opts )>

=head2 post( $route, %opts )

Shortcut for C<provide( 'POST', $route, %opts )>

=head2 put( $route, %opts )

Shortcut for C<provide( 'PUT', $route, %opts )>

=head2 del( $route, %opts )

Shortcut for C<provide( 'DELETE', $route, %opts )>

=head1 METHODS

The following methods will be available on importing classes/objects:

=head2 call( @args )

Calls the API, requesting the execution of a certain route. This is the
main way your API is used. The arguments it expects to receive and its
behavior are dependent on the L<McBain runner|"MCBAIN RUNNERS"> used. Refer to the docs
of the runner you wish to use for more information.

=head2 forward( $namespace, [ \%params ] )

For usage from within API methods; this simply calls a method of the
the API with the provided parameters (if any) and returns the result.
With C<forward()>, an API method can call other API methods or even
itself (for recursive operations).

C<$namespace> is the method and route to execute, in the format C<< <METHOD>:<ROUTE> >>,
where C<METHOD> is one of C<GET>, C<POST>, C<PUT>, C<DELETE>, and C<ROUTE>
starts with a forward slash.

=head2 is_root( )

Returns a true value if the module is the root topic of the API.
Mostly used internally and in L<McBain runner|"MCBAIN RUNNERS"> modules.

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

	# export the is_root() subroutine to the target topic,
	# so that it knows whether it is the root of the API
	# or not
	*{"${target}::is_root"} = sub {
		exists $INFO{$target};
	};

	# let the runner module do needed initializations,
	# as the init method usually needs the is_root subroutine,
	# this statement must come after exporting is_root()
	__PACKAGE__->init($target);

	# export the provide subroutine to the target topic,
	# so that it can define routes and methods.
	*{"${target}::provide"} = sub {
		my ($method, $name) = (shift, shift);
		my %opts = @_;

		# make sure the route starts and ends
		# with a slash, and prefix it with the topic
		$name = '/'.$name
			unless $name =~ m{^/};
		$name .= '/'
			unless $name =~ m{/$};
		$name = $topic.$name
			unless $topic eq '/';

		$INFO{$root}->{$name} ||= {};
		$INFO{$root}->{$name}->{$method} = \%opts;
	};

	# export shortcuts to the provide() subroutine
	# per http methods
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

	# export the call method, the one that actually
	# executes API methods
	*{"${target}::call"} = sub {
		my ($self, @args) = @_;
		return try {
			# ask the runner module to generate a standard
			# env hash-ref
			my $env = __PACKAGE__->generate_env(@args);

			# handle the request
			my $res = $self->forward($env->{METHOD}.':'.$env->{NAMESPACE}, $env->{PAYLOAD});

			# ask the runner module to generate an appropriate
			# response with the result
			return __PACKAGE__->generate_res($env, $res);
		} catch {
			# an exception was caught, ask the runner module
			# to format it as it needs
			return __PACKAGE__->handle_exception($_, @args);
		};
	};

	# export the forward method, which is both used internally
	# in call(), and can be used by API authors within API
	# methods
	*{"${target}::forward"} = sub {
		my ($self, $meth_and_route, $payload) = @_;

		my ($meth, $route) = split(/:/, $meth_and_route);

		# make sure route ends with a slash
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

	# we're done with exporting, now lets try to load all
	# child topics (if any), and collect their method definitions
	_load_topics($target);
}

# _find_root( $current_class )
# -- finds the root topic of the API, which might
#    very well be the module we're currently importing into

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

# _load_topics( $base, $limit )
# -- finds and loads the child topics of the class we're
#    currently importing into, automatically requiring
#    them and thus importing McBain into them as well

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

=head1 MANUAL

=head2 ANATOMY OF AN API

Writing an API with C<McBain> is easy. The syntax is short and easy to remember,
and the feature list is just what it needs to be - short and sweet.

The main idea of a C<McBain> API is this: a client requests the execution of a
method provided by the API, sending a hash of parameters. The API then executes the
method with the client's parameters, and produces a response in the format of a
hash. So basically, a C<McBain> API is a hash-in hash-out interface, at least
when L<used directly|McBain::Directly>. Every L<runner module|"MCBAIN RUNNERS">
will enforce a different format. For example, the L<PSGI|McBain::WithPSGI> and
L<Gearman::XS|McBain::WithGearmanXS> runners are both JSON-in JSON-out interfaces.

A C<McBain> API is built of one or more B<topics>, in a hierarchical structure.
A topic is a class that provides methods that are categorically similar. For
example, an API might have a topic called "math" that provides math-related
methods such as add, multiply, divide, etc.

Since topics are hierarchical, every API will have a root topic, which may have
zero or more child topics. The root topic if where your API begins, and it's
decision how to utilize it. If your API is short and simple, with methods that
cannot be categorized into different topics, then the entire API can live within the
root topic itself, with no child topics at all. If, however, you're building a
larger API, then the root topic might be empty, or it can provide general-purpose
methods that do not particularly fit in a specific topic, for example maybe a status
method that returns the status of the service, or an authentication method.

The name of a topic is calculated from the name of the package itself. The root
topic is always called C</> (forward slash), and its child topics are named
like their package names, in lowercase, relative to the root topic, with C</>
as a separator instead of Perl's C<::>, and starting with a slash.
For example, lets look at the following API packages:

	MyAPI				- the root topic, will be called "/"
	MyAPI::Math			- a child topic, will be called "/math"
	MyAPI::Math::Constants	- a child-of-child, will be called "/math/constants"
	MyAPI::Strings		- a child topic, will be called "/strings"

You will notice that the naming of the topics is similar to paths in HTTP URIs.
This is by design, since I wrote C<McBain> mostly for writing web applications
(with the L<PSGI|McBain::WithPSGI> runner), and the RESTful architecture fits
well with APIs whether they are HTTP-based or not.

=head2 CREATING TOPICS

To create a topic package, all you need to do is:

	use McBain;

This will import C<McBain> functions into the package, register the package
as a topic (possibly the root topic), and attempt to load all child topics, if there
are any. For convenience, C<McBain> will also import L<strict> and L<warnings> for
you.

Notice that using C<McBain> doesn't make your package an OO class. If you want your
API to be object oriented, you are free to form your classes however you want, for
example with L<Moo> or L<Moose>:

	package MyAPI;

	use McBain;
	use Moo;

	has 'some_attr' => ( is => 'ro' );

	1;

=head2 CREATING ROUTES AND METHODS

The resemblance with HTTP continues as we delve further into methods themselves. An API
topic defines B<routes>, and one or more B<methods> that can be executed on every
route. Just like HTTP, these methods are C<GET>, C<POST>, C<PUT> and C<DELETE>.

Route names are like topic names. They begin with a slash, and every topic I<can>
have a root route which is just called C</>. Every method defined on a route
will have a complete name (or path, if you will), in the format
C<< <METHOD_NAME>:<TOPIC_NAME><ROUTE_NAME> >>. For example, let's say we have a
topic called C</math>, and this topic has a route called C</divide>, with one
C<GET> method defined on this route. The complete name (or path) of this method
will be C<GET:/math/divide>.

By using this structure and semantics, it is easy to create CRUD interfaces. Lets
say your API has a topic called C</articles>. This topic can have the following
routes and methods:

	POST:/articles/		- Create a new article (root route /)
	GET:/articles/<ID>	- Read an article
	PUT:/articles/<ID>	- Update an article
	DELETE:/articles/<ID>	- Delete an article

Methods are defined using the L<get()|"get( $route, %opts )">, L<post()|"post( $route, %opts )">,
L<put()|"put( $route, %opts )"> and L<del()|"del( $route, %opts )"> subroutines.
The syntax is similar to L<Moose>'s antlers:

	get '/multiply' => (
		description => 'Multiplies two integers',
		params => {
			a => { required => 1, integer => 1 },
			b => { required => 1, integer => 1 }
		},
		cb => sub {
			my ($api, $params) = @_;

			return $params->{a} * $params->{b};
		}
	);

Of the three keys above (C<description>, C<params> and C<cb>), only C<cb>
is required. It takes the actual subroutine to execute when the method is
called. The subroutine will get two arguments: first, the root topic (either
its package name, or its object, if you're creating an object oriented API),
and a hash-ref of parameters provided to the method (if any).

You can provide C<McBain> with a short C<description> of the method, so that
C<McBain> can use it when documenting the API with L<mcbain2pod>.

You can also tell C<McBain> which parameters your method takes. The C<params>
key will take a hash-ref of parameters, in the format defined by L<Brannigan>
(see L<Brannigan::Validations> for a complete references). These will be both
enforced and documented.

=head2 CALLING METHODS FROM WITHIN METHODS

Methods are allowed to call other methods (whether in the same route or not),
and even call themselves recursively. This can be accomplished easily with
the L<forward()|"forward( $namespace, [ \%params ] )"> method. For example:

	get '/factorial => (
		description => 'Calculates the factorial of a number',
		params => {
			num => { required => 1, integer => 1 }
		},
		cb => sub {
			my ($api, $params) = @_;

			if ($params->{num} <= 1) {
				return 1;
			} else {
				return $api->forward('GET:/multiply', {
					one => $params->{num},
					two => $api->forward('GET:/factorial', { num => $params->{num} - 1 })
				});
			}
		}
	);

In the above example, notice how the C<GET:/factorial> method calls both
C<GET:/multiply> and itself.

=head2 EXCEPTIONS

TODO

=head1 MCBAIN RUNNERS

A runner module is in charge of loading C<McBain> APIs in a specific way.
The default runner, L<McBain::Directly>, is the simplest runner there is,
and is meant for using APIs directly from Perl code.

When a C<McBain> API is loaded, the selected runner module is actually
set as the base class of C<McBain>, thus tweaking its behavior. The runner
is in charge of whatever heavy lifting is required in order to turn
your API into a "service", or an "app", or whatever it is you think your
API needs to be.

The following runners are currently available:

=over

=item * L<McBain::Directly> - Directly use an API from Perl code.

=item * L<McBain::WithPSGI> - Turn an API into a Plack based, JSON-to-JSON
RESTful web application.

=item * L<McBain::WithGearmanXS> - Turn an API into a JSON-to-JSON
Gearman worker.

=back

The latter two completely change the way your API is used, and yet you can
see their code is very short.

You can easily create your own runner modules, so that your APIs can be used
in different ways. A runner module needs to implement the following interface:

=head2 init( $runner_class, $target_class )

This method is called when C<McBain> is first imported into an API topic.
C<$target_class> will hold the name of the class currently being imported to.

You can do whatever initializations you need to do here, possibly manipulating
the target class directly. You will probably only want to do this on the root
topic, which is why L</"is_root( )"> is available on C<$target_class>.

You can look at C<WithPSGI> and C<WithGearmanXS> to see how they're using the
C<init()> method. For example, in C<WithPSGI>, L<Plack::Component> is added
to the C<@ISA> array of the root topic, so that it turns into a Plack app. In
C<WithGearmanXS>, the C<init()> method is used to define a C<work()> method
on the root topic, so that your API can run as any standard Gearman worker.

=head2 generate_env( $runner_class, @call_args )

This method receives whatever arguments were passed to the L</"call( @args )">
method. It is in charge of returning a standard hash-ref that C<McBain> can use
in order to determine which route the caller wants to execute, and with what
parameters. Remember that the way C<call()> is invoked depends on the runner used.

The hash-ref returned I<must> have the following key-value pairs:

=over

=item * ROUTE - The route to execute (string).

=item * METHOD - The method to call on the route (string).

=item * PAYLOAD - A hash-ref of parameters to provide for the method. If no parameters
are provided, an empty hash-ref should be given.

=back

The returned hash-ref is called C<$env>, inspired by L<PSGI>.

=head2 generate_res( $runner_class, \%env, $result )

This method formats the result from a route before returning it to the caller.
It receives the C<$env> hash-ref (if needed), and the result from the route. In the
C<WithPSGI> runner, for example, this method encodes the result into JSON and 
returns a proper PSGI response array-ref.

=head2 handle_exception( $runner_class, $error, @args )

This method will be called whenever a route raises an exception, or otherwise your code
fails. The C<$error> variable will either be a standard L<exception hash-ref|"EXCEPTIONS">
(if an exception was thrown directly), or a scalar if it was Perl or some module you use
that failed, so it's the responsibility of this method to check.

The method should format the error before returning it to the user, similar to what
C<generate_res()> above performs, but it allows you to handle exceptions gracefully.

Whatever arguments were provided to C<call()> will be provided to this method as-is,
so that you can inspect or use them if need be. C<WithGearmanXS>, for example,
will get the L<Gearman::XS::Job> object and call the C<send_fail()> method on it,
to properly indicate the job failed.

=head1 CONFIGURATION AND ENVIRONMENT
   
C<McBain> itself requires no configuration files or environment variables.
However, when using/running APIs written with C<McBain>, the C<MCBAIN_WITH>
environment variable might be needed to tell C<McBain> the name of the
L<runner module|"MCBAIN RUNNERS"> to use. The default value is "Directly",
so L<McBain::Directly> is used. See the various C<McBain> runner modules
for more information.
 
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
