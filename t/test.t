#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More "no_plan" ;
# XXX use lib "/usr/local/lib" ;
use Moxad::Config ;

my $num_errs = 0 ;
my %configs = () ;
for ( my $i=1 ; $i <= 3 ; $i++ ) {
    my $cf = Moxad::Config->new( "t/config${i}.conf", "" ) ;
    if ( $cf->errors() ) {
        my @errors = $cf->errors() ;
        foreach my $error ( @errors ) {
            print STDERR "$error\n" ;
            $num_errs++ ;
        }
    }
    $configs{ $i } = $cf ;
}
exit(1) if ( $num_errs ) ;

my $num_sections ;

$num_sections = $configs{1}->get_sections() ;
is( $num_sections, 3, 'number sections of config1 (3)' ) ;

$num_sections = $configs{2}->get_sections() ;
is( $num_sections, 2, 'number sections of config2 (2)' ) ;

$num_sections = $configs{3}->get_sections() ;
is( $num_sections, 1, 'number sections of config3 (1)' ) ;

is( $configs{2}->get_keywords( "bikes" ), 3, 'number of keywords for bikes (3)' ) ;

is( $configs{2}->get_keywords( "crap" ), 0, 'number of keywords for crap (0)' ) ;

is( $configs{2}->get_values( "bikes", "yamaha" ), "good", 'value of yamaha is good' ) ;

is( $configs{3}->get_values( "foo", "bar" ), undef, 'no such value for foo/bar (undef)' ) ;

is ( $configs{1}->errors(), 0, 'number of errors of config1 (0)' ) ;
is ( $configs{2}->errors(), 0, 'number of errors of config2 (0)' ) ;
is ( $configs{3}->errors(), 1, 'number of errors of config3 after forced error (1)' ) ;
$configs{3}->clear_errors() ;
is ( $configs{3}->errors(), 0, 'number of errors of config3 after cleared errors (0)' ) ;

is( $configs{3}->get_values( "blah", "boink" ), undef, 'no such value for blah/boink (undef)' ) ;
is( $configs{3}->get_values( "1", "2" ), undef, 'no such value for 1/2 (undef)' ) ;
is ( $configs{3}->errors(), 2, 'number of errors of config3 after forced errors (2)' ) ;
$configs{3}->clear_errors() ;
is ( $configs{3}->errors(), 0, 'number of errors of config3 after cleared errors (0)' ) ;
