package Parcel::Track::KR::PostOffice;
# ABSTRACT: Parcel::Track driver for the ePOST Korea

use utf8;

use Moo;

our $VERSION = '0.001';

with 'Parcel::Track::Role::Base';

use HTML::Selector::XPath;
use HTML::TreeBuilder::XPath;
use HTTP::Tiny;

#
# to support HTTPS
#
use IO::Socket::SSL;
use Mozilla::CA;
use Net::SSLeay;

our $URI =
    'https://trace.epost.go.kr/xtts/servlet/kpl.tts.common.svl.SttSVL?target_command=kpl.tts.tt.epost.cmd.RetrieveOrderConvEpostPoCMD&sid1=%s';
our $AGENT = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';

sub BUILDARGS {
    my ( $class, @args ) = @_;

    my %params;
    if ( ref $args[0] eq 'HASH' ) {
        %params = %{ $args[0] };
    }
    else {
        %params = @args;
    }
    $params{id} =~ s/\D//g;

    return \%params;
}

sub uri { sprintf( $URI, $_[0]->id ) }

sub track {
    my $self = shift;

    my $res = HTTP::Tiny->new( agent => $AGENT )->get( $self->uri );
    return unless $res->{success};

    #
    # http://stackoverflow.com/questions/19703341/disabling-html-entities-expanding-in-htmltreebuilder-perl-module
    #
    my $tree = HTML::TreeBuilder::XPath->new;
    $tree->ignore_unknown(0);
    $tree->no_expand_entities(1);
    $tree->attr_encoded(1);
    $tree->parse( $res->{content} );
    $tree->eof;

    my %result = (
        from   => q{},
        to     => q{},
        result => q{},
        htmls  => [],
        descs  => [],
    );
    my $prefix = '/html/body/div/div/div/div';
    $result{from}   = $tree->findvalue("$prefix/table[1]/tbody/tr[1]/td[1]");
    $result{to}     = $tree->findvalue("$prefix/table[1]/tbody/tr[2]/td");
    $result{result} = sprintf( '%s %s',
        $tree->findvalue("$prefix/table[2]/tbody/tr/td[4]"),
        $tree->findvalue("$prefix/table[2]/tbody/tr/td[5]"),
    );

    $result{htmls} = [
        ( $tree->findnodes("$prefix/table[1]") )[0]->as_HTML,
        ( $tree->findnodes("$prefix/table[2]") )[0]->as_HTML,
        ( $tree->findnodes("$prefix/form/table") )[0]->as_HTML,
    ];

    my @elements = $tree->findnodes("$prefix/form/table/tbody/tr");
    for my $e (@elements) {
        my $index = 0;
        my @tds   = $e->look_down(
            '_tag', 'td',
            sub {
                return if $index++ > 3;
                return 1;
            }
        );
        push(
            @{ $result{descs} },
            map {
                my $desc = $_;
                $desc =~ s/(^\s+|\s+$)//gms;
                $desc =~ s/ +/ /gms;
                $desc;
            } join( q{ }, map $_->as_text, @tds ),
        );
    }

    return \%result;
}

1;

# COPYRIGHT

__END__

=for Pod::Coverage BUILDARGS


=attr id

=method track

=method uri


=head1 SEE ALSO

=for :list
* L<Parcel::Track>
* L<ePOST Korea|http://www.epost.go.kr>
