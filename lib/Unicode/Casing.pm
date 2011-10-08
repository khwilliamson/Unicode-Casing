package Unicode::Casing;    # pod is after __END__ in this file

require 5.010;  # Because of Perl bugs; can work on earlier Perls with care
use strict;
use warnings;
use Carp;
use B::Hooks::OP::Check; 
use B::Hooks::OP::PPAddr; 

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = ();

our @EXPORT = ();

our $VERSION = '0.09';

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
        return if $function eq '-load';
        my $user_sub;
        if (! defined ($user_sub = shift)) {
            croak("Missing CODE reference for $function");
        }
        if (ref $user_sub ne 'CODE') {
            croak("$user_sub is not a CODE reference");
        }
        if ($function ne 'uc' && $function ne 'lc'
            && $function ne 'ucfirst' && $function ne 'lcfirst'
            && ! ($function eq 'fc' && $^V ge v5.15.8))
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

sub fc ($) {
    use Unicode::UCD qw(casefold);
    my $return = "";

    foreach my $char (split //, $_[0]) { 
        if (defined (my $fold = casefold(ord $char)->{'full'}) {

            # $fold is a string of space-separated hex ordinals
            $return .= join "", map { chr hex } split / /, $fold;
        }
        else {
            $return .= $char;
        }
    }
    return $return;
}
        
        

1;
__END__

=encoding utf8

=head1 NAME

Unicode::Casing - Perl extension to override system case changing functions

=head1 SYNOPSIS

  use Unicode::Casing
            uc => \&my_uc, lc => \&my_lc,
            ucfirst => \&my_ucfirst, lcfirst => \&my_lcfirst;
  no Unicode::Casing;

  package foo::bar;
    use Unicode::Casing -load;
    sub import {
        Unicode::Casing->import(
            uc      => \&_uc,
            lc      => \&_lc,
            ucfirst => \&_ucfirst,
            lcfirst => \&_lcfirst,
        );
    }
    sub unimport {
        Unicode::Casing->unimport;
    }

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
context-sensitive case-changing.  (Because of bugs in earlier Perls, version
5.12 is required for this example to work properly.)

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

Note that there are problems with the standard case changing operation for
characters whose code points are between 128 and 255.  To get the correct
Unicode behavior, the strings must be encoded in utf8 (which the override
functions can force) or calls to the operations must be within the scope of C<use
feature 'unicode_strings'> (which is available starting in Perl version 5.12).

Note that there can be problems installing this (at least on Windows)
if using an old version of ExtUtils::Depends. To get around this follow
these steps:

=over

=item 1

upgrade ExtUtils::Depends

=item 2

force install B::Hooks::OP::Check

=item 3

force install B::Hooks::OP::PPAddr

=back

See L<http://perlmonks.org/?node_id=797851>.

=head1 AUTHOR

Karl Williamson, C<< <khw@cpan.org> >>,
with advice and guidance from various Perl 5 porters,
including Paul Evans, Burak Gürsoy, Florian Ragwitz, and Ricardo Signes.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Karl Williamson

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
If there were a CPAN module that let people use fc() for now until 5.16,
I'd be a lot more comfy with recommending it.  That way if something else
happens and it doesn't make it, they will still have something they can use.

Do you think that would be possible?

I do have my own versions that I use in unichars because I need *all*
possible Unicode casings available, but it's um, pretty stupidheaded.

    lc    lc_simple     lc_full
    uc    uc_simple     uc_full
    tc    tc_simple     tc_full
    fc    fc_simple     fc_full    fc_turkic

Plus various for dealing with the titlecasing/lowercasing
each word in a string.  

Note that none of those I just listed is the same as ucfirst().  
In my API below, that corresponds to tc_full_first().  tc()
does it to the whole string, just as uc() and lc() do.

Here it is without the module fluff.  The way I cache stuff
is just dumb, but it was easy to code up this way.  I don't
remember whether I sent this to you before.

--tom


use Unicode::UCD qw(casefold charinfo);

################################################################

# XXX: these should be LRU-caches, but are just OR-caches
our $FCI;
our $FCF;

UNITCHECK { 
    $FCI = {};
    $FCF = {};
}

################################################################

# forward declarations for functions so they work like the
# corresponding builtins (uc, lc, ucfirst)

sub all_casefold(_);
sub simple_casemap_all(_);

sub fc(_);
sub fc_simple(_);
sub fc_full(_);
sub fc_turkic(_);

# lc is builtin, which is full
sub lc_simple(_);
sub lc_full(_);

# uc is builtin, which is full
sub uc_simple(_);
sub uc_full(_);

# ucfirst is builtin, which is full, but it
# is the first char only, so you have to
# decide between first, all, or tc the start
# or a word and lc the rest fo it

sub tc_simple(_);
sub tc_full(_);

sub tc_simple_char(_);
sub tc_simple_first(_);
sub tc_simple_all(_);
sub tc_simple_words(_);

sub tc_full_char(_);
sub tc_full_first(_);
sub tc_full_all(_);
sub tc_full_words(_);

sub _tc_template_builder;

#########################################

# for completeness' sake
sub lc_full(_) { lc      shift }
sub uc_full(_) { uc      shift }
sub tc_full(_) { ucfirst shift }
sub tc(_)      { &tc_full }

sub tc_full_first(_) { &tc_full } 

sub lc_simple(_) {
    my $arg = shift;
    return (simple_casemap_all($arg))[0];
}

sub uc_simple(_) {
    my $arg = shift;
    return (simple_casemap_all($arg))[2];
}

sub tc_simple_char(_) {
    my $arg = shift;

    # croak "expected argument of length 1 code point" unless defined($arg) && (length($arg) == 1);

    return (simple_casemap_all($arg))[1];
}

sub tc_simple_all(_) {
    my $arg = shift;
    return join q() => map { tc_simple_char } (split //, $arg);
}

sub tc_full_all(_) {
    my $arg = shift;
    return join q() => map { tc_full_char } (split //, $arg);
}

sub tc_simple(_) { &tc_simple_first }
sub tc_simple_first(_) {
    my $arg = shift;
    substr($arg, 0, 1) = tc_simple_char(substr($arg, 0, 1));
    return $arg;
}

sub _tc_template_builder {

    my $WORD_RX = qr{
        \b 
        (?<first_grapheme> (?=\w) \X  )  
        (?<word_remainder>        \w* )
        \b
    }x;

    for my $style ("simple", "full") {
        no strict "refs";

        my $tc_char_func = \&{"tc_${style}_char"};
        my $lc_func      = \&{"lc_${style}"};

        *{"tc_${style}_words"} = sub(_) { 
            use strict "refs";
            my $arg = shift;
            $arg =~ s{
                $WORD_RX
            }{
                $tc_char_func->($1) . 
                    ( length($2) 
                        ? $lc_func->($2) 
                        : ""
                    )
            }xeg;
            return $arg;
        };

    } 
} 

sub all_casefold(_) {
    my $sf_string = "";
    my $tf_string = "";
    my $ff_string = "";

    my $orig = shift;

    for my $cp (map { ord } split //, $orig) { 
        my $casefold = $$FCF{$cp} ||= casefold($cp);
        if (defined $casefold) {
            my @full_fold_hex = split / /, $casefold->{"full"};
            my $full_fold_string =
                       join "", map {chr(hex($_))} @full_fold_hex;
            $ff_string .= $full_fold_string;
            my @turkic_fold_hex =
                           split / /, ($casefold->{"turkic"} ne "")
                                           ? $casefold->{"turkic"}
                                           : $casefold->{"full"};
            my $turkic_fold_string =
                           join "", map {chr(hex($_))} @turkic_fold_hex;
            $tf_string .= $turkic_fold_string;
        } else {
            $ff_string .= chr($cp);
            $tf_string .= chr($cp);
        } 
        if (defined $casefold && $casefold->{"simple"} ne "") {
            my $simple_fold_hex = $casefold->{"simple"};
            my $simple_fold_string = chr(hex($simple_fold_hex));
            $sf_string .= $simple_fold_string;
        } else {
            $sf_string .= chr($cp);
        } 
    }

    return ($sf_string, $tf_string, $ff_string);
}

sub fc(_)        { &fc_full }
sub fc_simple(_) { return (all_casefold(shift))[0] } 
sub fc_turkic(_) { return (all_casefold(shift))[1] } 
sub fc_full(_)   { return (all_casefold(shift))[2] } 

sub simple_casemap_all(_) {
    my $lc_string = "";
    my $tc_string = "";
    my $uc_string = "";

    my $orig = shift;

    for my $cp (map { ord } split //, $orig) { 
        my $charinfo = $$FCI{$cp} ||= charinfo($cp);

        if ($charinfo->{"lower"}) {
            $lc_string .= chr(hex($charinfo->{"lower"}));
        } else {
            $lc_string .= chr($cp);
        } 

        if ($charinfo->{"title"}) {
            $tc_string .= chr(hex($charinfo->{"title"}));
        } else {
            $tc_string .= chr($cp);
        } 

        if ($charinfo->{"upper"}) {
            $uc_string .= chr(hex($charinfo->{"upper"}));
        } else {
            $uc_string .= chr($cp);
        } 

    }
    return ($lc_string, $tc_string, $uc_string);
}

UNITCHECK  {
    _tc_template_builder();
} 

1;



