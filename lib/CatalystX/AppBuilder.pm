package CatalystX::AppBuilder;
use Moose;
use namespace::clean -except => qw(meta);

our $VERSION = '0.00001';

has appname => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has appmeta => (
    init_arg => undef,
    is => 'ro',
    isa => 'Moose::Meta::Class',
    lazy_build => 1
);

has debug => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
);

has version => (
    is => 'ro',
    isa => 'Str',
    required => 1,
    lazy_build => 1,
);

has superclasses => (
    is => 'ro',
    isa => 'Maybe[ArrayRef]',
    required => 1,
    lazy_build => 1,
);

has config => (
    is => 'ro',
    isa => 'HashRef',
    lazy_build => 1,
);

has plugins => (
    is => 'ro',
    isa => 'ArrayRef',
    lazy_build => 1,
);

sub _build_version      { '0.00001' }
sub _build_superclasses { }
sub _build_config {
    my $self = shift;
    my %config = (
        name => $self->appname,
    );
    return \%config;
}

sub _build_plugins {
    my $self = shift;
    my @plugins = ();
    if ($self->debug) {
        unshift @plugins, '-Debug';
    }
    return \@plugins;
}

sub BUILD {
    my $self = shift;

    my $appname = $self->appname;
    my $meta = Moose::Util::find_meta( $appname );
    if (! $meta || ! $appname->isa('Catalyst') ) {
        my %config = ( version => $self->version );
        if (my $superclasses = $self->superclasses) {
            foreach my $class (reverse @$superclasses) {
                if (! Class::MOP::is_class_loaded($class)) {
                    Class::MOP::load_class($class);
                }
            }
            $config{superclasses} = $superclasses;
        }

        $meta = Moose::Meta::Class->create( $appname => %config );

        if ($appname->isa('Catalyst')) {
            # Don't let the base class fool us!
            delete $appname->config->{home};
            delete $appname->config->{root};
        }

        # Fugly, I know, but we need to load Catalyst in the app's namespace
        # for manythings to take effect.
        eval <<"        EOCODE";
            package $appname;
            use Catalyst;
        EOCODE
        die if $@;
    }
    return $meta;
}

sub bootstrap {
    my $self = shift;
    my $appclass = $self->appname;
    $appclass->config( $self->config );

    my $caller = caller(1);
    if ($caller eq 'main' || $ENV{HARNESS_ACTIVE}) {
        $appclass->setup( @{ $self->plugins || [] } );
    }
}

sub inherited_path_to {
    my $self = shift;

    # XXX You have to have built the class
    my $meta = Moose::Util::find_meta($self->appname);

    my @inheritance;
    foreach my $class ($meta->linearized_isa) {
        next if ! $class->isa( 'Catalyst' );
        next if $class eq 'Catalyst';

        push @inheritance, $class;
    }

    return map { $_->path_to(@_)->stringify } @inheritance;
}

sub app_path_to {
    my $self = shift;

    return $self->appname->path_to(@_)->stringify;
}
    

__PACKAGE__->meta->make_immutable();

1;


__END__

=head1 NAME

CatalystX::AppBuilder - Build Your Application Instance Programatically

=head1 SYNOPSIS

    # In MyApp.pm
    my $builder = CatalystX::AppBuilder->new(
        appname => 'MyApp',
        plugins => [ ... ],
    )
    $builder->bootstrap();

=head1 DESCRIPTION

WARNING: YMMV regarding this module.

This module gives you a programatic interface to I<configuring> Catalyst
applications.

The main motivation to write this module is this: to write reusable Catalyst
appllications. For instance, if you build your MyApp::Base, you might want to
I<mostly> use MyApp::Base, but you may want to add or remove a plugin or two.
Perhaps you want to tweak just a single parameter.

Traditionally, your option then was to use catalyst.pl and create another
scaffold, and copy/paste the necessary bits, and tweak what you need.

After testing several approaches, it proved that the current Catalyst 
architecture (which is Moose based, but does not allow us to use Moose-ish 
initialization, since the Catalyst app instance does not materialize until 
dispatch time) did not allow the type of inheritance behavior we wanted, so
we decided to create a builder module around Catalyst to overcome this.
Therefore, if/when these obstacles (to us) are gone, this module may
simply dissappear from CPAN. You've been warned.

=head1 HOW TO USE

=head2 DEFINING A CATALYST APP

This module is NOT a "just-execute-this-command-and-you-get-catalyst-running"
module. For the simple applications, please just follow what the Catalyst
manual gives you.

However, if you I<really> wanted to, you can define a simple Catalyst
app like so:

    # in MyApp.pm
    use strict;
    use CatalystX::AppBuilder;
    
    my $builder = CatalystX::AppBuilder->new(
        debug  => 1, # if you want
        appname => "MyApp",
        plugins => [ qw(
            Authentication
            Session
            # and others...
        ) ],
        config  => { ... }
    );

    $builder->bootstrap();

=head2 DEFINING YOUR CatalystX::AppBuilder SUBCLASS

You can also create a subclass of CatalystX::AppBuilder, say, MyApp::Builder:

    package MyApp::Builder;
    use Moose;

    extends 'CatalystX::AppBuilder';

This will give you the ability to give it defaults to the various configuration
parameters:

    override _build_config => sub {
        my $config = super(); # Get what CatalystX::AppBuilder gives you
        $config->{ SomeComponent } = { ... };
    };

    override _build_plugins => sub {
        my $plugins = super(); # Get what CatalystX::AppBuilder gives you
        push @$plugins, "MyPlugin1", "MyPlugin2";
    };

Then you can simply do this instead of giving parameters to 
CatalystX::AppBuilder every time:

    # in MyApp.pm
    use MyApp::Builder;
    MyApp::Builder->new()->bootstrap();

=head2 EXTENDING A CATALYST APP USING 

Once you created your own MyApp::Builder, you can keep inheriting it to 
create custom Builders which in turn create custom Catalyst applications:

    package MyAnotherApp::Builder;
    use Moose;

    extends 'MyApp::Builder';

    override _build_superclasses => sub {
        return [ 'MyApp' ]
    }

    ... do your tweaking ...

    # in MyAnotherApp.pm
    use MyAnotherApp::Builder;

    MyAnotherApp::Builder->new()->bootstrap();

Voila, you just reused every inch of Catalyst app that you created via
inheritance!

=head2 INCLUDING EVERY PATH FROM YOUR INHERITANCE HIERARCHY

Components like Catalyst::View::TT, which in turn uses Template Toolkit
inside, allows you to include multiple directories to look for the 
template files.

This can be used to recycle the templates that you used in a base application.

CatalystX::AppBuilder gives you a couple of tools to easily include
paths that are associated with all of the Catalyst applications that are
inherited. For example, if you have MyApp::Base and MyApp::Extended,
and MyApp::Extended is built using MyApp::Extended::Builder, you can do 
something like this:

    package MyApp::Extended::Builder;
    use Moose;

    extends 'CatalystX::AppBuilder'; 

    override _build_superclasses => sub {
        return [ 'MyApp::Base' ]
    };

    override _build_config => sub {
        my $self = shift;
        my $config = super();

        $config->{'View::TT'}->{INCLUDE_PATH} = 
            [ $self->inherited_path_to('root') ];
        # Above is equivalent to 
        #    [ MyApp::Extended->path_to('root'), MyApp::Base->path_to('root') ]
    };

So now you can refer to some template, and it will first look under the
first app, then the base app, thus allowing you to reuse the templates.

=head1 ATTRIBUTES

=head2 appname 

The module name of the Catalyst application. Required.

=head2 appmeta 

The metaclass object of the Catalyst application. Users cannot set this.

=head2 debug

Boolean flag to enable debug output in the application

=head2 version

The version string to use (probably meaningless...)

=head2 superclasses

The list of superclasses of the Catalyst application.

=head2 config

The config hash to give to the Catalyst application.

=head2 plugins

The list of plugins to give to the Catalyst application.

=head1 TODO

Documentation. Samples. Tests.

=head1 AUTHOR

Daisuke Maki - C<< <daisuke@endeworks.jp> >>

=cut