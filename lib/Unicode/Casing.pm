package Unicode::Casing;    # pod is after __END__ in this file

use strict;
use warnings;
use Carp;
use B::Hooks::OP::Check; 
use B::Hooks::OP::PPAddr; 

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = ();

our @EXPORT = ();

our $VERSION = '0.05';

require XSLoader;
XSLoader::load('Unicode::Casing', $VERSION);

# List of references to functions that are overridden by this module
# anywhere in the program.  Each gets a unique id, which is its index
# into this list.
my @_function_list;

# The way it works is that each function that is overridden has a
# reference stored to it in the array.  The index in the array to it is
# stored in %^H with the key being the name of the overridden function,
# like 'uc'.  This keeps track of scoping.  A .xs function is set up to
# intercept calls to the overridden-functions, and it calls _dispatch
# with the name of the function which was being called and the string to
# change the case of. _dispatch looks up the function name in %^H to
# find the index which in turn yields the function reference.  If there
# is no overridden function, the core one is called instead.  (This can
# happen when part of the core code processing a call to one of these
# functions itself calls a casing function, as happens with Unicode
# table look-ups.)

sub _dispatch {
    my ($string, $function) = @_;

    # Called by the XS op-interceptor to look for the correct user-defined
    # function, and call it.
    #   $string is the scalar whose case is being changed
    #   $function is the generic name, like 'uc', of the case-changing
    #       function.

    return if ! defined $string;

    # This is the key that should be stored in the hash hints for this
    # function if overridden
    my $key = id_key($function);

    # For reasons I don't understand, the intermediate $hints_hash_ref cannot
    # be skipped; in 5.13.11 anyway.
    my $hints_hash_ref = (caller(0))[10];

    my $index = $hints_hash_ref->{$key};

    if (! defined $index) { # Not overridden
        return CORE::uc($string) if $function eq 'uc';
        return CORE::lc($string) if $function eq 'lc';
        return CORE::ucfirst($string) if $function eq 'ucfirst';
        return CORE::lcfirst($string) if $function eq 'lcfirst';
        return;
    }

    # Force scalar context and returning exactly one value;
    my $ret = &{$_function_list[$index]}($string);
    return $ret;
}

sub setup_key { # key into %^H for value returned from setup();
    return __PACKAGE__ . "_setup_" . shift;
}

sub id_key { # key into %^H for index into @_function_list
    return __PACKAGE__ . "_id_" . shift;
}

sub import {
    shift;  # Ignore 'casing' parameter.

    my %args;

    while (my $function = shift) {
        my $user_sub;
        if (! defined ($user_sub = shift)) {
            croak("Missing CODE reference for $function");
        }
        if (ref $user_sub ne 'CODE') {
            croak("$user_sub is not a CODE reference");
        }
        if ($function ne 'uc' && $function ne 'lc'
            && $function ne 'ucfirst' && $function ne 'lcfirst')
        {
            croak("$function must be one of: 'uc', 'lc', 'ucfirst', 'lcfirst'");
        }
        elsif (exists $args{$function}) {
            croak("Only one override for \"$function\" is allowed");
        }
        $args{$function} = 1;
    
        push @_function_list, $user_sub;
        $^H{id_key($function)} = scalar @_function_list - 1;

        # Remove any existing override in the current scope
        my $setup_key = setup_key($function);
        teardown($function, $^H{$setup_key}) if exists $^H{$setup_key};

        # Save code returned so can tear down upon unimport();
        $^H{$setup_key} = setup($function);
    }

    croak("Must specify at least one case override") unless %args;
    return;
}

sub unimport {
    foreach my $function (qw(lc uc lcfirst ucfirst)) {
        my $id = $^H{setup_key($function)};
        teardown($function, $id) if defined $id;
    }
    return;
}

1;
__END__

=head1 NAME

Unicode::Casing - Perl extension to override system case changing functions

=head1 SYNOPSIS

  use Unicode::Casing
            uc => \&my_uc, lc => \&my_lc,
            ucfirst => \&my_ucfirst, lcfirst => \&my_lcfirst;
  no Unicode::Casing;

=head1 DESCRIPTION

This module allows overriding the system-defined character case changing
functions.  Any time something in its lexical scope would
ordinarily call C<lc()>, C<lcfirst()>, C<uc()>, or C<ucfirst()> the
corresponding user-specified function will instead be called.  This applies to
direct calls, and indirect calls via the C<\L>, C<\l>, C<\U>, and C<\u>
escapes in double quoted strings and regular expressions.

Each function is passed a string to change the case of, and should return the 
case-changed version of that string.  Using, for example, C<\U> inside the
override function for C<uc()> will lead to infinite recursion, but the
standard casing functions are available via CORE::.  For example,
    
 sub my_uc {
    my $string = shift;
    print "Debugging information\n";
    return CORE::uc($string);
 }
 use Unicode::Casing uc => \&my_uc;
 uc($foo);

gives the standard upper-casing behavior, but prints "Debugging information"
first.

It is an error to not specify at least one override in the "use" statement.
Ones not specified use the standard version.  It is also an error to specify
more than one override for the same function.

C<use re 'eval'> is not needed to have the inline case-changing sequences
work in regular expressions.

Here's an example of a real-life application, for Turkish, that shows
context-sensitive case-changing.

 sub turkish_lc($) {
    my $string = shift;

    # Unless an I is before a dot_above, it turns into a dotless i (the
    # dot above being attached to the I, without an intervening other
    # Above mark; an intervening non-mark (ccc=0) would mean that the
    # dot above would be attached to that character and not the I)
    $string =~ s/I (?! [^\p{ccc=0}\p{ccc=Above}]* \x{0307} )/\x{131}/gx;

    # But when the I is followed by a dot_above, remove the dot_above so
    # the end result will be i.
    $string =~ s/I ([^\p{ccc=0}\p{ccc=Above}]* ) \x{0307}/i$1/gx;

    $string =~ s/\x{130}/i/g;

    return CORE::lc($string);
 }

A potential problem with context-dependent case changing is that the routine
may be passed insufficient context, especially with the in-line escapes like
C<\L>.

F<90turkish.t>, which comes with the distribution includes a full implementation
of all the Turkish casing rules.

=head1 AUTHOR

Karl Williamson, E<lt>khw@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Karl Williamson

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
