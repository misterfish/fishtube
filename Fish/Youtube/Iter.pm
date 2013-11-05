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

# Old way:
# Usage: while (my $i = iter each %hash)
#        while (my $i = iter each @array)
#        while (my $i = iter eachr $array_ref)
#        while (my $i = iter eachr $hash_ref)
#        while (my $i = iter eachr @$array_ref)
#        while (my $i = iter eachr %$hash_ref)

sub iter_old (@) {
    my ($k, $v) = @_;
    return unless defined $k;
    my $i = _Iter->new(
        a => $k,
        b => $v,
    );
    $i;
}

# New way:
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





__END__

# old version: pure perl
package __IterHash {
    use warnings;
    use strict;

    use 5.14.0;

    sub new {
        my ($c, @args) = @_;
        my $self;
        if (@args) {
            $self = {};
            for (my $i = 0; $i < @args; $i+=2) {
                my $k = $args[$i];
                my $v = $args[$i+1];
                $self->{$k} = $v;
            }
        }
        else {
            $self = {
                a => undef,
                b => undef,
            };
        }
        bless $self, __PACKAGE__;
    }

    sub k {
        my ($self) = @_;
        $self->{a};
    }

    sub v {
        my ($self) = @_;
        $self->{b};
    }

1}

