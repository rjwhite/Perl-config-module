# Read config file(s) with Perl module

## Description
This module is a set of OOP methods to read a config file and provide access
to its sections, keywords and values.  A section is a grouping of
   ***keyword = values***.
A section begins at the beginning of a line and the keywords for that
section are indented.  A keyword can point to a scalar value, an array of
values, or an associative array of values.

Lines can be continued across multiple lines by ending a line with a
backslash.  Values are separated by commas.
To have a comma or a backslash as part of the data, escape them with a backslash.

Other config files can be included, to any depth, via a ***#include*** line.

Comments begin with a '#' character (if it isn't a #include) and blank lines
are ignored.

To preserve whitespace around values, use matching single or double quotes
around a value.

A optional definitions file can be provided so that a different separator
than a comma can be given, restriction to a set of allowed values, and
provide the type of value there instead of in the main config file.
These can be specified for a specific keyword within a section, or
globally to a keyword that may be present in multiple sections.

If a definitions file is provided, then keywords cannot be in the config
file, unless they are defined in the definitions file.  Unless the option
'AcceptUndefinedKeywords' is provided and set to 'yes'.

If a 'type' is provided in both the config file and the definitions file
for a section/keyword, then they must match.  One does not over-ride
the other.

To see documentation, do a ***perldoc Moxad::Config.pm***

### Class methods
- new()
- set_debug()

### Instance methods
- get_sections()
- get_keywords()
- get_type()
- get_values()

## Config file example
    # This is a comment
    section-name1:
        keyword1 (scalar)   = value1
        keyword2            = value2
        keyword3            = 'this is a really big multi-line \
                               value with spaces on the end   '
        keyword4 (array)    = val1, val2, 'val 3   ', val4
        keyword5 (hash)     = v1 = this, \
                              v2 = " that ", \
                              v3 = fooey

    #include some/other/file.conf

    section-name2:
        keyword4            = This keyword4 is separate from the \
                              keyword4 in the section section-name1
        something           = 'This has a comma here \, in the data'

    section-name1:
        more-stuff          = more stuff for section-name1

## Definitions file example
     # This keyword1 will only apply to section section-name1
     keyword                = section-name1:keyword1
     type                   = array
     separator              = ;
     allowed-values         = val1, val2, val3 \
                              'val 4   '

     # this keyword2 will apply to all sections
     keyword                = keyword2
     type                   = hash
     separator              = ,

## Code example
    #!/usr/bin/env perl

    use strict ;
    use warnings ;
    use Moxad::Config ;

    Moxad::Config->set_debug(0) ;   # set no debugging (default)

    my $cfg1 = Moxad::Config->new(
                "test.conf",       # config file
                "test-defs.conf",  # definitions file
                { AcceptUndefinedKeywords => 'yes' } ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            print "ERROR: $error\n" ;
        }
        exit(1) ;
    }
    my @sections = $cfg1->get_sections() ;      # get sections
    foreach my $section ( @sections ) {
        print "section: $section\n" ;
        my @keywords = $cfg1->get_keywords( $section ) ;  # get keywords
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
