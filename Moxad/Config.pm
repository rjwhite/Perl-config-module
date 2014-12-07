# Copyright 2014 RJ White
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ---------------------------------------------------------------------
#
# OOB methods to process a config file
#
# format is:
#      # This is a comment
#      section-name1:
#          keyword1 (scalar)   = value1
#          keyword2            = value2
#          keyword3            = 'this is a really big multi-line \
#                                 value with spaces on the end   '
#          keyword4 (array)    = val1, val2, 'val 3   ', val4
#          keyword5 (hash)     = v1 = this, \
#                                v2 = " that ", \
#                                v3 = fooey
#      section-name2:
#          keyword4            = value1
#          ...
# - the 'type' of a value defaults to scalar and does not need to be given.
# - continuation lines have a backslash as the last character on a line.
# - supports #include files to any depth via recursion.
# - can (single or double) quote values to maintain whitespace.
# - multiple values use a comma as a separator.
# - you can provide commas in your values by escaping them with a backslash.
#   ie:  keyword = 'This has a comma here \, as part of this sentance'
# - to get a backslash in your values, escape it with another backslash.
#
# sample code to crawl through and print out all values
#
#   use Moxad::Config ;
#
#    Moxad::Config->set_debug(0) ;   # set no debugging (default)
#    
#    my $cfg1 = Moxad::Config->new( "test1.conf" ) ;
#    if ( $cfg1->errors() ) {
#        my @errors = $cfg1->errors() ;
#        foreach my $error ( @errors ) {
#            print "ERROR: $error\n" ;
#        }
#        exit(1) ;
#    }
#    my @sections = $cfg1->get_sections() ;      # get sections
#    foreach my $section ( @sections ) {
#        print "section: $section\n" ;
#        my @keywords = $cfg1->get_keywords( $section ) ;  # get keywords
#        foreach my $keyword ( @keywords ) {
#            print "\tkeyword: $keyword  " ;
#            my $type = $cfg1->get_type( $section, $keyword ) ;
#            print "($type)\n" ;
#            if ( $type eq "scalar" ) {
#                my $value = $cfg1->get_values( $section, $keyword ) ;
#                print "\t\t\'$value\'\n" ;
#            } elsif ( $type eq "array" ) {
#                my @values = $cfg1->get_values( $section, $keyword ) ;
#                foreach my $value ( @values ) {
#                    print "\t\t\'$value\'\n" ;
#                }
#            } elsif ( $type eq "hash" ) {
#                my %values = $cfg1->get_values( $section, $keyword ) ;
#                foreach my $key ( keys( %values )) {
#                    my $value = $values{ $key } ;
#                    print "\t\t$key = \'$value\'\n" ;
#                }
#            }
#        }
#    }
#
# RJ White
# rj@moxad.com
# Dec 2014

package Moxad::Config ;

use strict ;
use warnings ;

use constant ERRORS           => "errors" ;
use constant SECTIONS         => "sections" ;
use constant CURRENT_SECTION  => "section-name" ;
use constant VALUE_TYPES      => "value_types" ;

use constant TYPE_SCALAR      => "scalar" ;
use constant TYPE_ARRAY       => "array" ;
use constant TYPE_HASH        => "hash" ;
use constant TYPE_UNKNOWN     => "unknown" ;

use constant HIDE_COMMA       => "EvIlCoMmA" ;
use constant HIDE_BACKSLASH   => "EvIlBaCkSlAsH" ;

my $debug_value   = 0 ;


use Exporter ;
our @EXPORT = ( ) ;
our $ISA = qw( Exportter ) ;


# class method to create a new instance
#
# Inputs:
#       filename
# Returns:
#       instance
# Usage:
#       my $cfg1 = Moxad::Config->new( $file ) ;

sub new {
    my $class   = shift ;
    my $file    = shift ;

    my %instance = () ;

    $instance{ ERRORS }             = [] ;      # array of error messages
    $instance{ SECTIONS }           = {} ;      # our values
    $instance{ VALUE_TYPES }        = {} ;      # types of our values
    $instance{ CURRENT_SECTION }    = "none" ;  # current section name

    my $self = bless \%instance, $class ;

    my $ret = process_file( $self, $file ) ;    # ignore any bad return

    $self ;
}


# instance method to check for and get error messages.
# called in a scalar context, checks for errors.
# called in a array  context, returns error messages
#
# Inputs:
#       <none>
# Returns:
#       number of errors if scalar context
#       array of errors if array  context
# Usage:
#       if ( $cfg1->errors() ) {
#           my @errors = $cfg1->errors() ;
#           foreach my $error ( @errors ) {
#               print "You got a error dude: $error\n" ;
#           }
#           exit(1) ;
#       }

sub errors {
    my $self    = shift ;

    if ( ! ref( $self )) {
        die( "errors() is a instance method, not a class method\n" ) ;
    }
    return( @{$self->{ ERRORS }} ) ;
}


# instance method to get section names
#
# Inputs:
#       <none>
# Returns:
#       array of section names
# Usage:
#       my @sections = $cfg1->get_sections() ;

sub get_sections {
    my  $self = shift ;

    if ( ! ref( $self )) {
        die( "get_sections() is a instance method, not a class method\n" ) ;
    }

    my @sections = () ;
    foreach my $section ( keys( %{ $self->{ SECTIONS }} )) {
        push( @sections, $section ) ;
    }
    return( @sections ) ;
}


# instance method to get keyword names of a section
#
# Inputs:
#       section-name
# Returns:
#       array of keyword names
# Usage:
#       my @keywords = $cfg1->get_keywords( $section ) ;

sub get_keywords {
    my $self    = shift ;
    my $section = shift ;

    if ( ! ref( $self )) {
        die( "get_keyword is a instance method, not a class method\n" ) ;
    }

    my @keywords = () ;
    if (( not defined( $section )) or ( $section eq "" )) {
        my $error = "get_keywords(): No section name given" ;
        push( @$self{ ERRORS }, $error ) ;
        return( @keywords ) ;
    }

    if ( not defined( $self->{ SECTIONS }->{ $section } )) {
        return( @keywords ) ;   # empty list
    }

    foreach my $keyword ( keys( %{ $self->{ SECTIONS }->{ $section }} )) {
        push( @keywords, $keyword ) ;
    }
    return( @keywords ) ;
}


# instance method to get a type of a value
# can be scalar, array or hash
#
# Inputs:
#       section-name
#       keyword-name
# Returns:
#       type (scalar, array, hash)
# Usage:
#       my $type = $cfg1->get_type( $section, $keyword ) ;

sub get_type {
    my $self    = shift ;
    my $section = shift ;
    my $keyword = shift ;

    if ( ! ref( $self )) {
        die( "get_type() is a instance method, not a class method\n" ) ;
    }

    my %args = (
        "section"   => $section,
        "keyword"   => $keyword,
    ) ;
    my $type = TYPE_UNKNOWN ;

    # Do args checking
    foreach my $thing ( keys( %args )) {
        my $arg = $args{ $thing } ;
        if ( not defined( $arg )) {
            my $error = "get_type(): No $thing given" ;
            push( @$self{ ERRORS }, $error ) ;
            return( $type ) ;
        }
    }

    $type = $self->{ VALUE_TYPES }{ $section }{ $keyword } ;
    if ( not defined( $type )) {
        $type = TYPE_UNKNOWN ;
    }
    return( $type ) ;
}


# instance method to get the value(s)
# returns a scalar if the type is a scalar
# returns a array  if the type is an array
# returns a hash   if the type is a hash
#
# Inputs:
#       section-name
#       keyword-name
# Returns:
#       value if the type is a scalar
#       array of values if the type is an array
#       hash of values if the type is a hash
# Usage:
#       my $value = $cfg1->get_values( $section, $keyword ) ;
#       my @values = $cfg1->get_values( $section, $keyword ) ;
#       my %values = $cfg1->get_values( $section, $keyword ) ;

sub get_values {
    my $self    = shift ;
    my $section = shift ;
    my $keyword = shift ;

    if ( ! ref( $self )) {
        die( "get_values() is a instance method, not a class method\n" ) ;
    }

    my %args = (
        "section"   => $section,
        "keyword"   => $keyword,
    ) ;
    my $type = TYPE_UNKNOWN ;

    # Do args checking
    foreach my $thing ( keys( %args )) {
        my $arg = $args{ $thing } ;
        if ( not defined( $arg )) {
            my $error = "get_values(): No $thing given" ;
            push( @$self{ ERRORS }, $error ) ;
            return( $type ) ;
        }
    }

    $type = $self->{ VALUE_TYPES }{ $section }{ $keyword } ;
    if ( not defined( $type )) {
        my $error = "Unknonn type for section \'$section\' keyword \'$keyword\'" ;
        push( @$self{ ERRORS }, $error ) ;
        return( "" ) ;      # assume user wanted a scalar
    }

    if ( $type eq TYPE_SCALAR ) {
        return( $self->{ SECTIONS }{ $section }{ $keyword } ) ;
    } elsif ( $type eq TYPE_ARRAY ) {
        return( @{$self->{ SECTIONS }{ $section }{ $keyword }} ) ;
    } elsif ( $type eq TYPE_HASH ) {
        return( %{$self->{ SECTIONS }{ $section }{ $keyword }} ) ;
    } else {
        return( "" );       # cant happen
    }
}


# class method to set debugging on (non-0) or off (0)
#
# Inputs:
#       integer (0=off (default) or non-0=on)
# Returns:
#       previous value
# Usage:
#       Moxad::Config->set_debug(1)

sub set_debug {
    my $class   = shift ;
    my $value   = shift ;

    my $old_value = $debug_value ;

    $debug_value = $value ;

    dprint( "Debug set" ) if ( $value ) ;

    return( $old_value ) ;
}

# -------------------------------------------------------------
# stuff below here is not for user use

# internal non-OOP function to print a debug message
#
# Inputs:
#       message
# Returns:
#       0
# Usage:
#       dprint( "a debug message" ) ;

sub dprint {
    my $msg     = shift ;

    return if ( $debug_value ) == 0 ;

    print "debug: $msg\n" ;

    return(0) ;
}


# internal non-OOP function to read/process a file.
# called recursively when it encounters a #include
#
# Inputs:
#       filename
# Returns:
#       0 - ok
#       1 - not ok

sub process_file {
    my $self = shift ;
    my $file = shift ;

    my $line_num = 0 ;

    if (( not defined( $file )) or ( $file eq "" )) {
        my $error = "No file given" ;
        push( @$self{ ERRORS }, $error ) ;
        return(1) ;
    }
    dprint( "Processing file: $file" ) ;

    if ( ! -f $file ) {
        my $error = "No such file: $file" ;
        push( @$self{ ERRORS }, $error ) ;
        return(1) ;
    }

    my $fd ;
    if ( ! open( $fd, "<", $file )) {
        my $error = "Can\'t open: $file" ;
        push( @$self{ ERRORS }, $error ) ;
        return(1) ;
    }

    my $total_line = "" ;   # combined continuation lines

    # we might be in the middle of a section from a previous call
    # from a included config file.  Get our preserved section name
    my $section    = $self->{ CURRENT_SECTION } ;

    while ( my $line = <$fd> ) {
        $line_num++ ;
        chomp( $line ) ;
        next if ( $line eq "" ) ;       # skip blank lines

        if ( $line =~ /^\#include\s+(.*)\s*/ ) {
            my $ret = process_file( $self, $1 ) ;
            if ( $ret ) {
                close $fd ;
                return( $ret ) ;
            }
            dprint( "Back to processing file: $file" ) ;
            next ;
        }

        next if ( $line =~ /^\#/ ) ;    # skip comments

        # see if this is the start of a section
        # A section name must begin with alphanumeric

        if ( $line =~ /^\w/ ) {
            $line =~ s/:.*$// ;     # remove potential colon
            dprint( "starting a SECTION ($line) on line $line_num in $file" ) ;
            $self->{ CURRENT_SECTION } = $line ;
            $section = $line ;      # for quick use for this file
            next ;
        }

        # we have to be processing values (a keyword section)

        $line =~ s/^\s+// ;         # strip leading whitespace

        # see if it is a continuation line

        my $continu = 0 ;      # assume not a continuation line
        if ( $line =~ /\\$/ ) {
            dprint( "Got a continuation line on line $line_num in $file" ) ;
            # strip off continuation char but NOT any whitespace
            $line =~ s/\\$// ;

            $total_line .= $line ;      # add to previous input
            $continu = 1 ;
            next ;                      # go get the next line
        }

        if ( $total_line ne "" ) {
            $total_line .= $line ;      # last line of multi-line values
            $line = $total_line ;       # get all of it back into $line
            $total_line = "" ;          # re-initialize
        }

        # we now have everything we want on one line
        # separate out into the keyword and value(s)

        if ( $line !~ /^([\w\-\(\)\s)]+)\s*=\s*(.*)$/ ) {
            my $error = "Not a valid keyword entry on line $line_num " .
                "in $file: \'$line\'" ;
            push( @$self{ ERRORS }, $error ) ;
            close $fd ;
            return(1) ;
        }
        my $keyword = $1 ;
        my $values  = $2 ;

        $keyword =~ s/^\s+// ;      # remove leading  whitespace
        $keyword =~ s/\s+$// ;      # remove trailing whitespace
        $values  =~ s/^\s+// ;      # remove leading  whitespace
        $values  =~ s/\s+$// ;      # remove trailing whitespace

        dprint( "Before Type check: keyword=\'$keyword\' values=\'$values\'" ) ;

        # See what type of data it is: scalar, array, hash
        my $value_type = TYPE_SCALAR ;   # default to scalar value
        if ( $keyword =~ /^([\w\-)]+)\s*\(\s*(.*)\s*\)\s*$/ ) {
            $keyword = $1 ;
            my $type = $2 ;
            $type =~ tr/A-Z/a-z/ ;      # make lower case
            $type =~ s/^\s+// ;         # remove leading whitespace
            $type =~ s/\s+$// ;         # remove trailing whitespace

            if ( $type eq TYPE_SCALAR ) {
                $value_type = TYPE_SCALAR ;
            } elsif ( $type eq TYPE_ARRAY ) {
                $value_type = TYPE_ARRAY ;
            } elsif ( $type eq TYPE_HASH ) {
                $value_type = TYPE_HASH ;
            } else {
                my $error = "Invalid type ($type) on line $line_num " .
                    "in $file" ;
                push( @$self{ ERRORS }, $error ) ;
                close $fd ;
                return(1) ;
            }
            dprint( "Type \'$type\' for section \'" .
                $section . "\' keyword \'$keyword\'" ) ;
        }

        dprint( "have section \'$section\' keyword \'$keyword\' " .
            "with values \'$values\'" ) ;

        # if a user wants a backslash as part of the data, they had to
        # escape it.  Look for it and hide it for now before we look for
        # escaped other things, like value separators (commas)

        # This goofy syntax is because constants, which are implemented as
        # subroutines, need to be escaped in order to work in substitutions

        $values =~ s/\\\\/${\HIDE_BACKSLASH}/eg ;

        # if the user escapes a comma to have it part of the data,
        # then hide it for now

        $values =~ s/\\,/${\HIDE_COMMA}/eg ;

        # save our values, depending on the Type

        if ( $value_type eq TYPE_SCALAR ) {

            # A scalar. Do the easy stuff first
            # If the value previously existed, overwrite it.

            # put any commas back but with the backslashes
            $values =~ s/${\HIDE_COMMA}/,/g ;     

            # now put any dual backslashes back - but only one
            $values =~ s/${\HIDE_BACKSLASH}/\\/g ;     

            # now strip any balanced quotes that were used to preserve whitespace

            $values = $1 if ( $values =~ /^\"(.*)\"$/ ) ;
            $values = $1 if ( $values =~ /^\'(.*)\'$/ ) ;

            $self->{ SECTIONS }->{ $section }->{ $keyword } = $values ;

        } elsif ( $value_type eq TYPE_ARRAY ) {
            # A array.  # Just append it.
            # Don't check to see if a same value is already there.
            # It  is valid to have several repeats in the values.

            my @values = split( /,/, $values ) ;
            foreach my $value ( @values ) {
                # put any commas back but with the backslashes
                $value =~ s/${\HIDE_COMMA}/,/g ;     

                # now put any dual backslashes back - but only one
                $value =~ s/${\HIDE_BACKSLASH}/\\/g ;     

                dprint( "Pushing ARRAY value \'$value\' to keyword \'$keyword\'" ) ;

                # create the empty anonymous array if it doesn't exist
                my $ref = $self->{ SECTIONS }->{ $section }->{ $keyword } ;
                if ( ! defined( $ref )) {
                    $self->{ SECTIONS }->{ $section }->{ $keyword } = [] ;
                }

                # get rid of whitespace
                $value =~ s/^\s+// ;
                $value =~ s/\s+$// ;

                # now strip any balanced quotes that were used to preserve whitespace

                $value = $1 if ( $value =~ /^\"(.*)\"$/ ) ;
                $value = $1 if ( $value =~ /^\'(.*)\'$/ ) ;

                # now save the value

                $ref = $self->{ SECTIONS }->{ $section }->{ $keyword } ;
                push( @{$ref}, $value ) ;
            }
        } elsif ( $value_type eq TYPE_HASH ) {
            # A hash

            my @values = split( /,/, $values ) ;
            foreach my $value ( @values ) {
                # put any commas back but with the backslashes
                $value =~ s/${\HIDE_COMMA}/,/g ;     

                # now put any dual backslashes back - but only one
                $value =~ s/${\HIDE_BACKSLASH}/\\/g ;     

                dprint( "Pushing HASH value \'$value\' to keyword \'$keyword\'" ) ;

                # create the empty anonymous hash if it doesn't exist
                my $ref = $self->{ SECTIONS }->{ $section }->{ $keyword } ;
                if ( ! defined( $ref )) {
                    $self->{ SECTIONS }->{ $section }->{ $keyword } = {} ;
                }

                # get rid of whitespace
                $value =~ s/^\s+// ;
                $value =~ s/\s+$// ;

                # we should now have a 'keyword = value'

                my $real_value ;
                my $real_keyword ;
                if ( $value =~ /^([\w-]+)\s*=\s*(.*)\s*$/ ) {
                    $real_keyword = $1 ;
                    $real_value   = $2 ;
                } else {
                    my $error = "Invalid hash given ($value) on line " .
                        "$line_num in $file" ;
                    push( @$self{ ERRORS }, $error ) ;
                    close $fd ;
                    return(1) ;
                }

                # now strip any balanced quotes that were used to preserve whitespace

                $real_value = $1 if ( $real_value =~ /^\"(.*)\"$/ ) ;
                $real_value = $1 if ( $real_value =~ /^\'(.*)\'$/ ) ;

                # now save the value

                $ref = $self->{ SECTIONS }->{ $section }->{ $keyword } ;
                ${$ref}{ $real_keyword} = $real_value ;
            }
        }

        # set a value type
        $self->{ VALUE_TYPES }->{ $section }->{ $keyword } = $value_type ;

    }
    close $fd ;

    return(0) ;
}

1;

__END__

=head1 NAME

Moxad::Config - Read config file(s)

=head1 SYNOPSIS

use Moxad::Config ;

=head1 DESCRIPTION

This module is a set of OOP methods to read a config file and provide
access to its sections, keywords and values.  A section is a grouping
of keyword = values.  A section begins at the beginning of a line
and the keywords for that section are indented.  A keyword can point
to a scalar value, an array of values, or a associative array of values.

Lines can be continued across multiple lines by ending a line with a
backslash.  Values are separated by commas.  To have a comma or a 
backslash as part of the data, escape them with a backslash.

Other config files can be included, to any depth, via a #include line.

Comments begin with a '#' character (if it isn't a #include) and blank
lines are ignored.

To preserve whitespace around values, use matching single or double
quotes around a value.

=head1 Config file example

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


=head1 Class methods

=head2 new

 my $cfg1 = Moxad::Config->new( $file ) ;

=head2 set_debug

 my $old_debug_value = Moxad::Config->set_debug(0) ;   # off (default)
 my $old_debug_value = Moxad::Config->set_debug(1) ;   # on

=head1 Instance methods

=head2 get_sections

 my @sections = $cfg1->get_sections() ;

=head2 get_keywords

 my @keywords = $cfg1->get_keywords( $section ) ;

=head2 get_type

 my $type = $cfg1->get_type( $section, $keyword ) ;

=head2 get_values

 my $value  = $cfg1->get_values( $section, $keyword ) ; # scalar
 my @values = $cfg1->get_values( $section, $keyword ) ; # array
 my %values = $cfg1->get_values( $section, $keyword ) ; # hash

=head1 Code sample

 #!/usr/bin/env perl
 
 use strict ;
 use warnings ;
 use Moxad::Config ;
 
 Moxad::Config->set_debug(0) ;  # off - default
 
 my $cfg1 = Moxad::Config->new( "test.conf" ) ;
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
         print "\tkeyword: $keyword " ;

         # get the type to determine which way to call get_values()
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

=head1 SEE ALSO

Melbourne, Australia.  I hear it's nice.

=head1 AUTHOR

RJ White, E<lt>rj@moxad.comE<gt>

=head1 COPYRIGHT AND LICENSE

 Copyright 2014 RJ White
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
