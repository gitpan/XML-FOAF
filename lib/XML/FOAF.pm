# $Id: FOAF.pm,v 1.4 2003/01/27 23:52:33 btrott Exp $

package XML::FOAF;
use strict;

use RDF::Core::Model;
use RDF::Core::Storage::Memory;
use RDF::Core::Model::Parser;
use RDF::Core::Resource;

use XML::FOAF::Person;
use base qw( XML::FOAF::ErrorHandler );

use vars qw( $VERSION $NAMESPACE );
$VERSION = '0.01';
$NAMESPACE = 'http://xmlns.com/foaf/0.1/';

sub new {
    my $class = shift;
    my $foaf = bless { }, $class;
    my($stream, $base_uri) = @_;
    my $store = RDF::Core::Storage::Memory->new;
    $foaf->{model} = RDF::Core::Model->new(Storage => $store);
    my %pair;
    if (UNIVERSAL::isa($stream, 'URI')) {
        require LWP::Simple;
        my $data = LWP::Simple::get($stream);
        $foaf->{raw_data} = \$data;
        %pair = ( Source => $data, SourceType => 'string' );
        unless ($base_uri) {
            my $uri = $stream->clone;
            my @segs = $uri->path_segments;
            $uri->path_segments(@segs[0..$#segs-1]);
            $base_uri = $uri->as_string;
        }
    } elsif (ref($stream) eq 'SCALAR') {
        $foaf->{raw_data} = $stream;
        %pair = ( Source => $$stream, SourceType => 'string' );
    } elsif (ref $stream) {
        ## In case we need to verify this data later, we need to read
        ## it in now. This isn't great for memory usage, though.
        my $data;
        while (read $stream, my($chunk), 8192) {
            $data .= $chunk;
        }
        $foaf->{raw_data} = \$data;
        %pair = ( Source => $data, SourceType => 'string' );
    } else {
        $foaf->{raw_data} = $stream;
        %pair = ( Source => $stream, SourceType => 'file' );
    }
    my $parser = RDF::Core::Model::Parser->new(
                       Model => $foaf->{model},
                       BaseURI => $base_uri,
                       %pair);
    eval {
        ## Turn off warnings, because RDF::Core::Parser gives a bunch of
        ## annoying warnings about $ce->{parsetype} being undefined at
        ## line 636.
        local $^W = 0;
        $parser->parse;
    };
    if ($@) {
        return $class->error($@);
    }
    $foaf;
}

sub person {
    my $foaf = shift;
    my $enum = $foaf->{model}->getStmts(undef,
    RDF::Core::Resource->new('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'),
    RDF::Core::Resource->new($NAMESPACE . 'Person')
    ) or return;
    XML::FOAF::Person->new($foaf, $enum->getFirst->getSubject);
}

sub assurance {
    my $foaf = shift;
    my $res = RDF::Core::Resource->new('http://xmlns.com/wot/0.1/assurance');
    my $enum = $foaf->{model}->getStmts(undef, $res);
    my $stmt = $enum->getFirst or return;
    $stmt->getObject->getLabel;
}

sub verify {
    my $foaf = shift;
    my $sig_url = $foaf->assurance or return;
    require LWP::Simple;
    my $sig = LWP::Simple::get($sig_url);
    require Crypt::OpenPGP;
    my $pgp = Crypt::OpenPGP->new( AutoKeyRetrieve => 1,
                                   KeyServer => 'pgp.mit.edu' );
    my %arg = ( Signature => $sig );
    my $raw = $foaf->{raw_data};
    if (ref($raw)) {
        $arg{Data} = $$raw;
    } else {
        $arg{Files} = $raw;
    }
    my $valid = $pgp->verify(%arg) or return 0;
    $valid;
}

1;
__END__

=head1 NAME

XML::FOAF - Parse FOAF (Friend of a Friend) data

=head1 SYNOPSIS

    use XML::FOAF;
    use URI;
    my $foaf = XML::FOAF->new(URI->new('http://foo.com/my.foaf'));
    print $foaf->person->mbox, "\n";

=head1 DESCRIPTION

I<XML::FOAF> provides an object-oriented interface to FOAF (Friend of a Friend)
data.

=head1 USAGE

=head2 XML::FOAF->new($data [, $base_uri ])

Reads in FOAF data from I<$data> and parses it. Returns a I<XML::FOAF> object
on success, C<undef> on error. If an error occurs, you can call

    XML::FOAF->errstr

to get the text of the error.

I<$base_uri> is the base URI to be used in constructing absolute
URLs from resources defined in your FOAF data, and is required unless I<$data>
is a URI object, in which case the I<$base_uri> can be obtained from that
URI.

I<$data> can be any of the following:

=over 4

=item * A URI object

An object blessed into any I<URI> subclass. For example:

    my $uri = URI->new('http://foo.com/my.foaf');
    my $foaf = XML::FOAF->new($uri);

=item * A scalar reference

This indicates a reference to a string containing the FOAF data. For example:

    my $foaf_data = <<FOAF;
    ...
    FOAF
    my $foaf = XML::FOAF->new(\$foaf_data, 'http://foo.com');

=item * A filehandle

An open filehandle from which the FOAF data can be read. For example:

    open my $fh, 'my.foaf' or die $!;
    my $foaf = XML::FOAF->new($fh, 'http://foo.com');

=item * A file name

A simple scalar containing the name of a file containing the FOAF data. For
example:

    my $foaf = XML::FOAF->new('my.foaf', 'http://foo.com');

=back

=head2 $foaf->person

Returns a I<XML::FOAF::Person> object representing the main identity in the
FOAF file.

=head2 $foaf->assurance

If the FOAF file indicates a PGP signature in I<wot:assurance>, the URL
for the detatched signature file will be returned, C<undef> otherwise.

=head2 $foaf->verify

Attempts to verify the FOAF file using the PGP signature returned from
I<assurance>. I<verify> will fetch the public key associated with the
signature from a keyserver. If no PGP signature is noted in the FOAF file,
or if an error occurs, C<undef> is returned. If the signature is invalid,
C<0> is returned. If the signature is valid, the PGP identity (name and
email address, generally) of the signer is returned.

=head1 REFERENCES

http://xmlns.com/foaf/0.1/

http://rdfweb.org/foaf/

=head1 LICENSE

I<XML::FOAF> is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR & COPYRIGHT

Except where otherwise noted, I<XML::FOAF> is Copyright 2003 Benjamin
Trott, cpan@stupidfool.org. All rights reserved.

=cut
