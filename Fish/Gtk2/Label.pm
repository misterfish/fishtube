package Fish::Gtk2::Label;

use Gtk2;

use strict;
use warnings;

# This is how you add custom signals. 

use Glib::Object::Subclass
    Gtk2::Label::,
    # can add custom signals
    signals => {
        #blah => {},
    },
;

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new;

    $self->{opts} = {};

    $class->set_label($self, @args) if @args; 
    $self->modify_bg('normal', Gtk2::Gdk::Color->new(255,255,255,255));
    bless $self, $class;
}

# class or object method
sub set_label {
    my ($s) = @_;

    # class 
    shift unless ref $s;

    my ($self, $text, $opt) = @_;

    if ($opt) {
        $self->{opt} = $opt;
    }
    else {
        $opt = $self->{opt};
    }

    my $size = $opt->{size} // '';
    my $color = $opt->{color} // '';

    my $s1 = '';
    my $s2 = '';

    # ignore size -- do it with rc
    my $ss = $size ? qq|size="$size"|  : '';
    #my $ss = '';
    my $sc = $color ? qq|color="$color"| : '';
    my @s = ($ss, $sc);

    $s1 = "<span " . join ' ', @s if @s;
    $s1 .= ">" if $s1;

    $s2 = '</span>' if $s1;

    my $markup = $s1 . $text . $s2;

#D 'markup', $markup;

    $markup =~ s/\&/&amp;/g;

    my ($al, $txt, $accel_char) = Pango->parse_markup($markup);
    $self->set_attributes($al);
    $self->SUPER::set_label($text);
}




1;


