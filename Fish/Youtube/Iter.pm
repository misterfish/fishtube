package _Iter {
    use Class::XSAccessor 
        constructor => 'new',
        accessors => {
            k => 'a',
            i => 'a',
            v => 'b',
        },
        ;
1}

package Fish::Youtube::Iter;

use 5.14.0;

use warnings;
use strict;

use base 'Exporter';

BEGIN {
    our @EXPORT = qw, iter iterr iterab iterrab ,;
}

# Usage: while (my $i = iter %hash)
#        while (my $i = iter @array)
#        while (my $i = iterr $array_ref)
#        while (my $i = iterr $hash_ref)
#        while (my $i = iter @$array_ref)
#        while (my $i = iter %$hash_ref)

sub iter (+) {
    my ($ref) = @_;
    my $r = ref $ref;

    my ($k, $v) = 
        $r eq 'ARRAY' ? each @$ref : 
        $r eq 'HASH' ? each %$ref :
        die "Need @ or % to iter.";

    return unless defined $k;

    my $i = _Iter->new(
        a => $k,
        b => $v,
    );
    $i;
}

sub iterr($) {
    my ($ref) = @_;
    my $r = ref $ref;

    return 
        $r eq 'ARRAY' ? iter(@$ref) :
        $r eq 'HASH' ? iter(%$ref) :
        die "Need arrayref or hashref to iterr.";
}

sub iterab_old(@) {
    my ($package, $filename, $line) = caller;
    my $eval = qq| (\$${package}::a, \$${package}::b ) = \@_ |;
    eval $eval;
}

sub iterab (+) {
    my ($ref) = @_;
    my $r = ref $ref;
    my ($k, $v) = 
        $r eq 'ARRAY' ? each @$ref : 
        $r eq 'HASH' ? each %$ref :
        die "Need @ or % to iterab.";
    return unless defined $k;
    my ($package, $filename, $line) = caller;
    # security? XX
    my $eval = qq| (\$${package}::a, \$${package}::b ) = (\$k, \$v) |;
    eval $eval;
    1;
}

sub iterrab ($) {
    my ($ref) = @_;
    my $r = ref $ref;
    my ($k, $v) = 
        $r eq 'ARRAY' ? each @$ref :
        $r eq 'HASH' ? each %$ref :
        die "Need arrayref or hashref to iterrab.";
    return unless defined $k;
    my ($package, $filename, $line) = caller;
    # security? XX
    my $eval = qq| (\$${package}::a, \$${package}::b ) = (\$k, \$v) |;
    eval $eval;
    1;
}

1;
