package Fish::Youtube::UO;

use 5.10.0;

BEGIN {
    use Exporter ();
    @ISA = qw/Exporter/;
    @EXPORT = 'o';
    push @INC, "$ENV{HOME}/bin";
}

use strict;
use warnings;

# Handy way to generate anonymous classes -- but Class::Generate isn't in
# the debian packages, and maybe isn't well maintained either.
use Class::Generate 'class';

# generate anonymous object with -> accessors.

# e.g.:
# $obj = o( a=>1, b=>undef, %hash=>{}, hash_ref=>{}, @ary=>[], ary_ref=>[],
# '+-idx' => -1)

sub o {
    state $idx = 0;
    my %stuff = @_;
    my $class_name = 'anon' . ++$idx;
    my (@class_def, @init);
    while (my ($k, $v) = each %stuff) {
        my $sigil;
        my $add_counter_methods;
        if ($k =~ /^ ( % | @ | \+- ) (.+) /x) {
            if ($1 eq '+-') {
                $sigil = '$';
                $add_counter_methods = 1;
                $k = $2;
            }
            else {
                $sigil = $1;
                $k = $2;
            }
        }
        else {
            $sigil = '$';
        }
        push @class_def, $k, $sigil;
        push @init, $k,  $v;

        # if var name is e.g. +-idx, this adds magic methods ->idx_inc and
        # ->idx_dec.
        if ($add_counter_methods) {
            # e.g. push @class_def, '&idx_inc' => q{ $idx++ }
            # man Class::Generate
            push @class_def, "&${k}_inc", qq{ \$$k++ };
            push @class_def, "&${k}_dec", qq{ \$$k-- };
        }

    }

    # class anon1 => [ x => '$', y => '%', ... ];
    #class $class_name => [ @class_def ];
    class $class_name => { @class_def };

    my $obj = $class_name->new(@init);

    return $obj;
}

1;
