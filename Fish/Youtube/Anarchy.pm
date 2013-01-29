#!/usr/bin/perl 
package Fish::Youtube::Anarchy;

use 5.10.0;

use Moose;

sub error;
sub war;

use Math::Trig ':pi';

use Time::HiRes 'sleep';

use Fish::Youtube::Utility;

# arc1 begin
my @perc1 = (.23, 1);
# arc1 end
my @perc2 = (.5, 0);
# arc2 begin
my @perc3 = (.5, 0);
# arc2 end
my @perc4 = (.79, 1);
# arc3 begin
my @perc5 = (0, .75);
# arc3 end
my @perc6 = (1, .38);
# circle center
my @perc7 = (.5, .6);
# circle radius
my $perc8 = .32;

has r => (
    is => 'rw',
    isa => 'Num',
);

has width => (
    is => 'ro',
    isa => 'Num',
);

has height => (
    is => 'ro',
    isa => 'Num',
);

has args1 => (
    is => 'rw',
    isa => 'ArrayRef',
);

has args2 => (
    is => 'rw',
    isa => 'ArrayRef',
);

has args3 => (
    is => 'rw',
    isa => 'ArrayRef',
);

has args4 => (
    is => 'rw',
    isa => 'ArrayRef',
);

has args5 => (
    is => 'rw',
    isa => 'ArrayRef',
);

has args6 => (
    is => 'rw',
    isa => 'ArrayRef',
);

has args7 => (
    is => 'rw',
    isa => 'ArrayRef',
);

has lw => (
    is => 'rw',
    isa => 'Num',
);

sub BUILD {

    my ($self, @args) = @_;

    # use width as master scale factor
    my ($w, $h) = ($self->width, $self->height);

    my $jitter1 = .2 * $w;
    my $jitter2 = .05 * $w;
    my $jitter3 = .03 * $w;
    my $jitter4 = .02 * $w;
    my $jitter5 = .1 * $w;
    my $jitter6 = .08 * $w;

    my $lw = .05 * $w;
    $self->lw($lw);

    my @cur = ($perc1[0] * $w, $perc1[1] * $h);

    $cur[0] += myrand(0, $jitter4);
    $cur[1] += myrand(-1 * $jitter4, 0);

    my @end = ($perc2[0] * $w, $perc2[1] * $h);
    $end[0] += myrand(0, $jitter2);
    $end[1] += myrand(0, $jitter2);

    my @d1 = (0, 0);
    $d1[0] += myrand(0, $jitter3);
    $d1[1] += myrand(0, $jitter3);

    my @ctl1 = ($cur[0] + ($end[0] - $cur[0]) * 1/2 + $d1[0], $end[1] + ($cur[1] - $end[1]) * 1/2 + $d1[1]);
    my @ctl2 = @ctl1;

    $self->args1([@cur]);
    $self->args2( [$ctl1[0], $ctl1[1], $ctl2[0], $ctl2[1], $end[0], $end[1]]);

    @cur = ($perc3[0] * $w, 0);
    $cur[0] += myrand(-1 * $jitter2, 0);
    $cur[1] += myrand(0, $jitter2);

    @end = ($perc4[0] * $w, $perc4[1] * $h);
    $end[0] += myrand(-1 * $jitter2, 0);
    $end[1] += myrand(-1 * $jitter2, 0);

    $self->args3([@cur]);

    @d1 = (0, 0);
    $d1[0] += myrand(-1 * $jitter4, 0);
    $d1[1] += myrand(-1 * $jitter4, 0);

    @ctl1 = ($cur[0] + ($end[0] - $cur[0]) * 1/2 + $d1[0], $cur[1] + ($end[1] - $cur[1]) * 1/2 + $d1[1]);
    @ctl2 = @ctl1;

    $self->args4([$ctl1[0], $ctl1[1], $ctl2[0], $ctl2[1], $end[0], $end[1]]);

    @cur = ($perc5[0] * $w, $perc5[1] * $h);
    $cur[0] += myrand(0, $jitter5);
    $cur[1] += myrand(-1 * $jitter5, 0);

    @end = ($perc6[0] * $w, $perc6[1] * $h);
    $end[0] += myrand(0, $jitter5);
    $end[1] += myrand(-1 * $jitter5, 0);

    @d1 = (0, 0);
    $d1[0] += myrand(-1 * $jitter6, $jitter6);
    $d1[1] += myrand(-1 * $jitter6, $jitter6);

    @ctl1 = ($cur[0] + ($end[0] - $cur[0]) * 1/2 + $d1[0], $cur[1] + ($end[1] - $cur[1]) * 1/2 + $d1[1]);
    @ctl2 = @ctl1;

    $self->args5([@cur]);
    $self->args6([$ctl1[0], $ctl1[1], $ctl2[0], $ctl2[1], $end[0], $end[1]]);

    my @center = ($perc7[0] * $w, $perc7[1] * $h);
    my $r = $perc8 * $w;

    $center[0] += myrand(0, $jitter2);
    $center[1] += myrand(-1 * $jitter2, 0);
    $r += myrand(-1 * $jitter2, 1);

    $self->r($r);

    $self->args7([$center[0], $center[1], $r, 0, 2 * pi]);
}

# given perc, return cairo surface.
sub draw {
    my ($self, $perc, $opt) = @_;
    $opt //= {};

    my $last = $opt->{last} // 0;

    my ($w, $h) = ($self->width, $self->height);

    my ($t1, $t2, $t3, $t4);
    if ($perc < .25) {
        ($t1, $t2, $t3, $t4) = (4 * $perc, 0, 0, 0);
    }
    elsif ($perc < .5) {
        ($t1, $t2, $t3, $t4) = (1, 4 * ($perc - .25), 0, 0);
    }
    elsif ($perc < .75) {
        ($t1, $t2, $t3, $t4) = (1, 1, 4 * ($perc - .5), 0);
    }
    else {
        ($t1, $t2, $t3, $t4) = (1, 1, 1, 4 * ($perc - .75));
    }

    #DC $t1, $t2, $t3, $t4;

    my $surface = Cairo::ImageSurface->create('argb32', $w, $h);

    my $cr = Cairo::Context->create($surface);                                                            

    $cr->set_source_rgba (1, 1, 1, 1);
    # fills the whole thing.
    $cr->paint;

    $cr->set_line_width($self->lw);

    if ($last) {
        $cr->set_source_rgba (0, 0, 0, 1);
    }
    else {
        # b70000
        $cr->set_source_rgba (0xb7 / 255, 0, 0, 1);
    }

    $cr->move_to(@{$self->args1});
    $cr->curve_to(@{$self->args2});

    $cr->set_dash(0, $w * $t1 , 1000);
    $cr->stroke;

    if ($t2) {
        $cr->move_to(@{$self->args3});
        $cr->curve_to(@{$self->args4});

        $cr->set_dash(0, $w * $t2, 1000);
        $cr->stroke;
    }

    if ($t3) {
        $cr->move_to(@{$self->args5});
        $cr->curve_to(@{$self->args6});

        $cr->set_dash(0, $w * $t3, 1000);
        $cr->stroke;
    }

    if ($t4) {
        $cr->new_sub_path;

        $cr->arc(@{$self->args7});

        $cr->set_dash(0, 2 * pi * $self->r * $t4, 1000);
        $cr->stroke;
    }

    return $surface;

}

#almost inc
sub myrand {
    my ($a, $b) = @_;
    $a < $b or die;
    $a + rand ($b - $a);
}

sub error {
    my @s = @_;
    die join ' ', @s, "\n";
}

sub war {
    my @s = @_;
    warn join ' ', @s, "\n";
}


1;
