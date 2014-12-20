#!/usr/bin/env perl

use strict ;
use warnings ;
use Moxad::Config ;

my $file        = "test.conf" ;
my $defs_file   = "test-defs.conf" ;

my $version = $Moxad::Config::VERSION ;
print "Version = $version\n" ;

Moxad::Config->set_debug(0) ;

my $cfg1 = Moxad::Config->new( 
    $file,
    $defs_file,
    { 'poo' => 'crap', 'AcceptUndefinedKeywords' => 'foo' } ) ;

if ( $cfg1->errors() ) {
    my @errors = $cfg1->errors() ;
    foreach my $error ( @errors ) {
        print "ERROR: $error\n" ;
    }
    exit(1) ;
}

my @sections = $cfg1->get_sections() ;
foreach my $section ( @sections ) {
    print "section: $section\n" ;
    my @keywords = $cfg1->get_keywords( $section ) ;
    foreach my $keyword ( @keywords ) {
        print "\tkeyword: $keyword  " ;

        my $type = $cfg1->get_type( $section, $keyword ) ;
        print "($type)\n" ;
        if ( $type eq "scalar" ) {
            my $value = $cfg1->get_values( $section, $keyword ) ;
            print "\t\t\'$value\'\n" ;
        } elsif ( $type eq "array" ) {
            my @values = $cfg1->get_values( $section, $keyword ) ;
            foreach my $value ( @values ) {
                print "\t\t\'$value\'\n" ;
            }
        } elsif ( $type eq "hash" ) {
            my %values = $cfg1->get_values( $section, $keyword ) ;
            foreach my $key ( keys( %values )) {
                my $value = $values{ $key } ;
                print "\t\t$key = \'$value\'\n" ;
            }
        }
    }
}

exit 0 ;
