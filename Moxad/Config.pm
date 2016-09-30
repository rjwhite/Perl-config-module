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
# - multiple values use a comma as a separator by default.
# - you can provide separators in your values by escaping them with a backslash.
#   ie:  keyword = 'This has a comma here \, as part of this sentence'
# - to get a backslash in your values, escape it with another backslash.
#
# A optional definitions file can be provided so that a different
# separator than a comma can be given, restriction to a set of
# allowed values, and provide the type of value there instead of in
# the main config file.  These can be specified for a specific keyword
# within a section, or globally to a keyword that may be present in
# multiple sections.
#
# If a definitions file is provided, then keywords cannot be in the
# config file, unless they are defined in the definitions file.
# Unless the option 'AcceptUndefinedKeywords' is provided and set
# to 'yes'.
# If a 'type' is provided in both the config file and the definitions
# file for a section/keyword, then they must match.  One does not
# over-ride the other.
# The optional definitions file format is:
#      # This is a comment
#      keyword        = section-name1:keyword1
#      type           = array
#      separator      = ;
#      allowed-values = val1, val2, val3 \
#                       'val 4   '
#
#      keyword        = keyword2
#      type           = hash
#      separator      = ,
#
# sample code to crawl through and print out all values:
#
#    #!/usr/bin/env perl
#    use strict ;
#    use warnings ;
#    use Moxad::Config ;
#
#    Moxad::Config->set_debug(0) ;   # set no debugging (default)
#    
#    my $cfg1 = Moxad::Config->new(
#                   "test1.conf",       # config file
#                   "test1-defs.conf",  # definitions file
#                   { AcceptUndefinedKeywords => 'yes' } ) ;
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
use Readonly ;
use version ; our $VERSION = qv('0.0.5') ;

Readonly my $ERRORS                     => "errors" ;
Readonly my $SECTIONS                   => "sections" ;
Readonly my $CURRENT_SECTION            => "section-name" ;
Readonly my $VALUE_TYPES                => "value_types" ;
Readonly my $ORDERED_SECTION_NAMES      => "section-names" ;
Readonly my $CONFIG_FILENAME            => "file" ;
Readonly my $DEFS_FILENAME              => "defsfile" ;

# used for processing data in optional definitions file
Readonly my $DEFS_TYPES                 => "def_type" ;
Readonly my $DEFS_KEYWORDS              => "def_keywords" ;
Readonly my $DEFS_ALLOWED               => "def_allow" ;
Readonly my $DEFS_SEPARATOR             => "def_sep" ;
Readonly my $DEFS_ALL_SECTIONS          => "def_ALL" ;

Readonly my $TYPE_SCALAR                => "scalar" ;
Readonly my $TYPE_ARRAY                 => "array" ;
Readonly my $TYPE_HASH                  => "hash" ;
Readonly my $TYPE_UNKNOWN               => "unknown" ;

Readonly my $HIDE_SEPARATOR             => "EvIlCoMmA" ;
Readonly my $HIDE_BACKSLASH             => "EvIlBaCkSlAsH" ;

Readonly my $DEFAULT_SEPARATOR          => "," ;

Readonly my $ACCEPT_UNDEFINED_KEYWORDS  => "AcceptUndefinedKeywords" ;

my $debug_value   = 0 ;


use Exporter ;
our @EXPORT = () ;
our @ISA = qw( Exporter ) ;


# class method to create a new instance
#
# Inputs:
#       filename
#       definitions file.  Can be a empty string.
#       hash of options
# Returns:
#       instance
# Usage:
#       my $cfg1 = Moxad::Config->new( $file ) ;

sub new {
    my $class       = shift ;
    my $file        = shift ;
    my $defs_file   = shift ;
    my $options_ref = shift ;

    my %instance = () ;

    $instance{ $ERRORS }                    = [] ;      # array of errors
    $instance{ $ORDERED_SECTION_NAMES }     = [] ;      # section names
    $instance{ $SECTIONS }                  = {} ;      # our values
    $instance{ $VALUE_TYPES }               = {} ;      # types of our values
    $instance{ $CURRENT_SECTION }           = "none" ;  # current section name
    $instance{ $ACCEPT_UNDEFINED_KEYWORDS } = 1 ;       # allow any keywords
    $instance{ $CONFIG_FILENAME }           = $file ;   # allow any keywords

    if (( not defined( $defs_file )) or ( $defs_file eq "" )) {
        # there is no defs file
        $defs_file = "" ;
    } else {
        # there is a defs file so assume we've defined ALL valid keywords
        $instance{ $ACCEPT_UNDEFINED_KEYWORDS } = 0 ;
    }
    $instance{ $DEFS_FILENAME } = $defs_file ;

    # check if we specifically allow undefined keywords
    if ( defined( $options_ref ) and ( ref( $options_ref ) eq "HASH" )) {
        dprint( "we have a options hash" ) ;
        if ( defined( ${$options_ref}{ $ACCEPT_UNDEFINED_KEYWORDS } ) and
          ( ${$options_ref}{ $ACCEPT_UNDEFINED_KEYWORDS } =~ /^yes$/i )) {
            $instance{ $ACCEPT_UNDEFINED_KEYWORDS } = 1 ;
            dprint( "set $ACCEPT_UNDEFINED_KEYWORDS" ) ;
        }
    }

    my $self = bless \%instance, $class ;

    my $ret = process_file( $self, $file, $defs_file ) ;

    return( $self ) ;
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
    return( @{$self->{ $ERRORS }} ) ;
}



# instance method to clear error messages.
#
# Inputs:
#       <none>
# Returns:
#   instance identifier
# Usage:
#       $cfg1->clear_errors() ;

sub clear_errors {
    my $self    = shift ;

    if ( ! ref( $self )) {
        die( "clear_errors() is a instance method, not a class method\n" ) ;
    }
    @{$self->{ $ERRORS }} = ()  ;
    return( $self ) ;
}


# instance method to reload the config file.  Zero everything out
#
# Inputs:
#       <none>
# Returns:
#   instance identifier
# Usage:
#       $cfg1->reload() ;

sub reload {
    my $self    = shift ;

    if ( ! ref( $self )) {
        die( "reload() is a instance method, not a class method\n" ) ;
    }

    dprint( "Reloading..." ) ;

    @{$self->{ $ERRORS }}                = () ;
    @{$self->{ $ORDERED_SECTION_NAMES }} = () ;
    %{$self->{ $SECTIONS }}              = () ;
    %{$self->{ $VALUE_TYPES }}           = () ;

    my $defs_file = $self->{ $DEFS_FILENAME } ;
    my $file      = $self->{ $CONFIG_FILENAME } ;

    my $ret = process_file( $self, $file, $defs_file ) ;

    return( $self ) ;
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
    foreach my $section ( @{$self->{ $ORDERED_SECTION_NAMES }} ) {
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
        push( @$self{ $ERRORS }, $error ) ;
        return( @keywords ) ;
    }

    if ( not defined( $self->{ $SECTIONS }->{ $section } )) {
        return( @keywords ) ;   # empty list
    }

    foreach my $keyword ( keys( %{ $self->{ $SECTIONS }->{ $section }} )) {
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
    my $type = $TYPE_UNKNOWN ;

    # Do args checking
    foreach my $thing ( keys( %args )) {
        my $arg = $args{ $thing } ;
        if ( not defined( $arg )) {
            my $error = "get_type(): No $thing given" ;
            push( @$self{ $ERRORS }, $error ) ;
            return( $type ) ;
        }
    }

    $type = $self->{ $VALUE_TYPES }{ $section }{ $keyword } ;
    if ( not defined( $type )) {
        $type = $TYPE_UNKNOWN ;
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
#       undef if value not available
# Usage:
#       my $value  = $cfg1->get_values( $section, $keyword ) ;
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
    my $type = $TYPE_UNKNOWN ;

    # Do args checking
    foreach my $thing ( keys( %args )) {
        my $arg = $args{ $thing } ;
        if ( not defined( $arg )) {
            my $error = "get_values(): No $thing given" ;
            push( @$self{ $ERRORS }, $error ) ;
            return( $type ) ;
        }
    }

    $type = $self->{ $VALUE_TYPES }{ $section }{ $keyword } ;
    if ( not defined( $type )) {
        my $error = "No value found for section \'$section\' keyword \'$keyword\'" ;
        push( @$self{ $ERRORS }, $error ) ;
        return( undef ) ;
    }

    if ( $type eq $TYPE_SCALAR ) {
        return( $self->{ $SECTIONS }{ $section }{ $keyword } ) ;
    } elsif ( $type eq $TYPE_ARRAY ) {
        return( @{$self->{ $SECTIONS }{ $section }{ $keyword }} ) ;
    } elsif ( $type eq $TYPE_HASH ) {
        return( %{$self->{ $SECTIONS }{ $section }{ $keyword }} ) ;
    } else {
        my $error = "Unknown type for section \'$section\' keyword \'$keyword\'" ;
        push( @$self{ $ERRORS }, $error ) ;
        return( undef ) ;       # cant happen
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
#       object instance
#       filename
#       definitions file
# Returns:
#       0 - ok
#       1 - not ok

sub process_file {
    my $self        = shift ;
    my $file        = shift ;
    my $defs_file   = shift ;

    my $line_num = 0 ;

    if (( not defined( $file )) or ( $file eq "" )) {
        my $error = "No file given" ;
        push( @$self{ $ERRORS }, $error ) ;
        return(1) ;
    }
    dprint( "Processing file: $file" ) ;

    if ( ! -f $file ) {
        my $error = "No such file: $file" ;
        push( @$self{ $ERRORS }, $error ) ;
        return(1) ;
    }

    # See if there is a defs file.
    # It should only be non-empty on the top-level call to here
    # and not recursive calls made below

    if ( $defs_file ne "" ) {
        my $ret = process_defs_file( $self, $defs_file ) ;
        return( $ret ) if ( $ret ) ;
    }

    my $fd ;
    if ( ! open( $fd, "<", $file )) {
        my $error = "Can\'t open: $file" ;
        push( @$self{ $ERRORS }, $error ) ;
        return(1) ;
    }

    my $total_line = "" ;   # combined continuation lines
    my $num_errs = 0 ;

    # we might be in the middle of a section from a previous call
    # from a included config file.  Get our preserved section name
    my $section = $self->{ $CURRENT_SECTION } ;

    while ( my $line = <$fd> ) {
        $line_num++ ;
        chomp( $line ) ;
        next if ( $line eq "" ) ;       # skip blank lines
        next if ( $line =~ /^\s+$/ ) ;  # skip lines that are only whitespace

        if ( $line =~ /^\#include\s+(.*)\s*/ ) {
            my $ret = process_file( $self, $1 ) ;
            if ( $ret ) {
                close $fd ;
                return( $ret ) ;
            }
            dprint( "Back to processing file: $file" ) ;
            next ;
        }

        next if ( $line =~ /^\s*\#/ ) ;    # skip comments

        # see if this is the start of a section
        # A section name must begin with alphanumeric

        if ( $line =~ /^\w/ ) {
            $line =~ s/:\s*$// ;     # remove potential colon
            dprint( "starting a SECTION ($line) on line $line_num in $file" ) ;
            $self->{ $CURRENT_SECTION } = $line ;
            $section = $line ;      # for quick use for this file

            # if we haven't seen it before, save into an ordered
            # array of section names.  get_sections() will use this.

            if ( not defined( $self->{ $SECTIONS }->{ $section } )) {
                push( @$self{ $ORDERED_SECTION_NAMES }, $line ) ;
            }

            next ;
        }

        # we have to be processing values (a keyword section)

        $line =~ s/^\s+// ;             # strip leading whitespace

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

        if ( $line !~ /^([\w\-\(\)\s)]+)    # keyword
                         \s*=\s*            # =
                         (.*)               # value
                         $/x ) {            # end of line
            my $error = "Not a valid keyword entry on line $line_num " .
                "in $file: \'$line\'" ;
            push( @$self{ $ERRORS }, $error ) ;
            $num_errs++ ;
            next ;
        }
        my $keyword = $1 ;
        my $values  = $2 ;

        # remove leading and trailing whitespace
        $keyword =~ s/^\s+// ;
        $keyword =~ s/\s+$// ;
        $values  =~ s/^\s+// ;
        $values  =~ s/\s+$// ;

        dprint("Before Type check: keyword=\'$keyword\' values=\'$values\'");

        # See what type of data it is: scalar, array, hash
        # look for a data type hint:  keyword (type) = value(s)

        my $value_type = "$TYPE_UNKNOWN" ;   # default to unknown
        if ( $keyword =~ /^
                           ([\w\-)]+)       # keyword
                           \s*              # whitespace
                           \(\s*(.*)\s*\)   # (type)
                           \s*$/x ) {       # whitespace till end of line
            $keyword = $1 ;
            my $type = $2 ;
            $type =~ tr/A-Z/a-z/ ;      # make lower case
            $type =~ s/^\s+// ;         # remove leading whitespace
            $type =~ s/\s+$// ;         # remove trailing whitespace

            if ( $type eq $TYPE_SCALAR ) {
                $value_type = $TYPE_SCALAR ;
            } elsif ( $type eq $TYPE_ARRAY ) {
                $value_type = $TYPE_ARRAY ;
            } elsif ( $type eq $TYPE_HASH ) {
                $value_type = $TYPE_HASH ;
            } else {
                my $error = "Invalid type ($type) on line $line_num " .
                    "in $file" ;
                push( @$self{ $ERRORS }, $error ) ;
                $num_errs++ ;
                next ;
            }
            dprint( "Type \'$type\' for section \'" .
                $section . "\' keyword \'$keyword\'" ) ;
        }

        dprint( "have section \'$section\' keyword \'$keyword\' " .
            "with values \'$values\'" ) ;

        # make sure the keyword is allowed
        if ( $self->{ $ACCEPT_UNDEFINED_KEYWORDS } == 0 ) {
            my $k = $self->{ $DEFS_KEYWORDS }->{ $section }->{ $keyword } ;
            if ( not defined( $k )) {
                $k = $self->{ $DEFS_KEYWORDS }->{ $DEFS_ALL_SECTIONS }->{ $keyword } ;
            }
            if ( not defined( $k )) {
                my $error = "keyword ($keyword) not allowed, found " .
                    "on line $line_num in $file" ;
                push( @$self{ $ERRORS }, $error ) ;
                $num_errs++ ;
                next ;
            }
        }

        # See if a type was defined in the definitions file.

        my $def_type = $self->{ $DEFS_TYPES}->{ $section }->{ $keyword } ;
        if ( not defined( $def_type )) {
            $def_type = $self->{ $DEFS_TYPES}->{ $DEFS_ALL_SECTIONS }->{ $keyword }
        }
        # set type from definitions if not given in config file
        if ( defined( $def_type ) and ( $value_type eq $TYPE_UNKNOWN )) {
            $value_type = $def_type ;
        }
        # If still unknown, default to scalar
        $value_type = $TYPE_SCALAR if ( $value_type eq $TYPE_UNKNOWN ) ;

        # check for discrepancy
        if ( defined( $def_type ) and ( $def_type ne $value_type )) {
            my $error = "Type given in defs file ($def_type) does not " .
                "match type given in config file ($value_type) for section " .
                "\'$section\', keyword \'$keyword\' on line " .
                "$line_num in $file" ;
            push( @$self{ $ERRORS }, $error ) ;
            $num_errs++ ;
            next ;
        }

        # now dealing with the values...

        # if a user wants a backslash as part of the data, they had to
        # escape it.  Look for it and hide it for now before we look for
        # escaped other things, like value separators (commas)

        $values =~ s/\\\\/$HIDE_BACKSLASH/eg ;

        # if the user escapes the separator to have it part of the data,
        # then hide it for now.  It's *probably* a comma, but maybe not...

        my $separator ;
        $separator = $self->{ $DEFS_SEPARATOR }->{ $section }->{ $keyword } ;
        if ( not defined( $separator )) {
            $separator = $self->{ $DEFS_SEPARATOR }->{ $DEFS_ALL_SECTIONS }->{ $keyword } ;
            if ( not defined( $separator )) {
                $separator = $DEFAULT_SEPARATOR ;
            }
        }

        $values =~ s/\\${separator}/$HIDE_SEPARATOR/eg ;

        # save our values, depending on the Type

        if ( $value_type eq $TYPE_SCALAR ) {

            # A scalar. Do the easy stuff first
            # If the value previously existed, overwrite it.

            # put any commas back but with the backslashes
            $values =~ s/$HIDE_SEPARATOR/${separator}/g ;     

            # now put any dual backslashes back - but only one
            $values =~ s/$HIDE_BACKSLASH/\\/g ;     

            # now strip any balanced quotes that were used to preserve whitespace

            $values = $1 if ( $values =~ /^\"(.*)\"$/ ) ;
            $values = $1 if ( $values =~ /^\'(.*)\'$/ ) ;

            # See if value allowed

            if ( ! value_allowed( $self, $section, $keyword, $values )) {
                my $error = "Value (\'$values\') not allowed for keyword " .
                    "\'$keyword\' on line $line_num in $file" ;
                push( @$self{ $ERRORS }, $error ) ;
                $num_errs++ ;
                next ;
            }

            $self->{ $SECTIONS }->{ $section }->{ $keyword } = $values ;

        } elsif ( $value_type eq $TYPE_ARRAY ) {
            # A array.  # Just append it.
            # Don't check to see if a same value is already there.
            # It  is valid to have several repeats in the values.

            my @values = split( /${separator}/, $values ) ;
            foreach my $value ( @values ) {
                # put any commas back but without the backslashe
                $value =~ s/$HIDE_SEPARATOR/${separator}/g ;     

                # now put any dual backslashes back - but only one
                $value =~ s/$HIDE_BACKSLASH/\\/g ;     

                dprint( "Pushing ARRAY value \'$value\' to keyword \'$keyword\'" ) ;

                # create the empty anonymous array if it doesn't exist
                my $ref = $self->{ $SECTIONS }->{ $section }->{ $keyword } ;
                if ( ! defined( $ref )) {
                    $self->{ $SECTIONS }->{ $section }->{ $keyword } = [] ;
                }

                # get rid of whitespace
                $value =~ s/^\s+// ;
                $value =~ s/\s+$// ;

                # now strip any balanced quotes that were used to preserve whitespace

                $value = $1 if ( $value =~ /^\"(.*)\"$/ ) ;
                $value = $1 if ( $value =~ /^\'(.*)\'$/ ) ;

                # See if value allowed

                if ( ! value_allowed( $self, $section, $keyword, $value )) {
                    my $error = "Value (\'$value\') not allowed for keyword " .
                        "\'$keyword\' on line $line_num in $file" ;
                    push( @$self{ $ERRORS }, $error ) ;
                    $num_errs++ ;
                    next ;
                }

                # now save the value

                $ref = $self->{ $SECTIONS }->{ $section }->{ $keyword } ;
                push( @{$ref}, $value ) ;
            }
        } elsif ( $value_type eq $TYPE_HASH ) {
            # A hash

            my @values = split( /${separator}/, $values ) ;
            foreach my $value ( @values ) {
                # put any commas back but with the backslashes
                $value =~ s/$HIDE_SEPARATOR/${separator}/g ;     

                # now put any dual backslashes back - but only one
                $value =~ s/$HIDE_BACKSLASH/\\/g ;     

                dprint( "Pushing HASH value \'$value\' to keyword \'$keyword\'" ) ;

                # create the empty anonymous hash if it doesn't exist
                my $ref = $self->{ $SECTIONS }->{ $section }->{ $keyword } ;
                if ( ! defined( $ref )) {
                    $self->{ $SECTIONS }->{ $section }->{ $keyword } = {} ;
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
                    push( @$self{ $ERRORS }, $error ) ;
                    $num_errs++ ;
                    next ;
                }

                # now strip any balanced quotes that were used to preserve whitespace

                $real_value = $1 if ( $real_value =~ /^\"(.*)\"$/ ) ;
                $real_value = $1 if ( $real_value =~ /^\'(.*)\'$/ ) ;

                # See if value allowed

                if ( ! value_allowed( $self, $section, $keyword, $real_value )) {
                    my $error = "Value (\'$real_value\') not allowed for keyword " .
                        "\'$keyword\' on line $line_num in $file" ;
                    push( @$self{ $ERRORS }, $error ) ;
                    $num_errs++ ;
                    next ;
                }

                # now save the value

                $ref = $self->{ $SECTIONS }->{ $section }->{ $keyword } ;
                ${$ref}{ $real_keyword} = $real_value ;
            }
        }

        # set a value type
        $self->{ $VALUE_TYPES }->{ $section }->{ $keyword } = $value_type ;

    }
    close $fd ;

    if ( $num_errs ) {
        return(1) ;
    } else {
        return(0) ;
    }
}


# internal non-OOP function to read/process a definitions file.
# should only be called once.
#
# Inputs:
#       object instance
#       definitions file
# Returns:
#       0 - ok
#       1 - not ok

sub process_defs_file {
    my $self        = shift ;
    my $defs_file   = shift ;

    my $line_num = 0 ;
    my %valid_types = (
        'scalar'    => $TYPE_SCALAR,
        'hash'      => $TYPE_HASH,
        'array'     => $TYPE_ARRAY,
    ) ;

    # return successfully if nothing to do
    if (( not defined( $defs_file )) or ( $defs_file eq "" )) {
        return(0) ;
    }

    dprint( "Processing defs file: $defs_file" ) ;

    if ( ! -f $defs_file ) {
        my $error = "No such definitions file: $defs_file" ;
        push( @$self{ $ERRORS }, $error ) ;
        return(1) ;
    }

    my $fd ;
    if ( ! open( $fd, "<", $defs_file )) {
        my $error = "Can\'t open: $defs_file" ;
        push( @$self{ $ERRORS }, $error ) ;
        return(1) ;
    }

    my $total_line = "" ;   # combined continuation lines

    my @lines = <$fd> ;     # just suck it all in
    close( $fd ) ;

    my $current_section = $DEFS_ALL_SECTIONS ;
    my $current_keyword = "" ;

    foreach my $line ( @lines ) {
        $line_num++ ;
        chomp( $line ) ;
        next if ( $line eq "" ) ;           # skip blank lines

        next if ( $line =~ /^\s*\#/ ) ;     # skip comments

        # see if it is a continuation line

        my $continu = 0 ;      # assume not a continuation line
        if ( $line =~ /\\$/ ) {
            dprint( "Got a continuation line on line $line_num in $defs_file" ) ;
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

        if ( $line !~ /^
                        ([\w\-)]+)      # keyword
                        \s*=\s*         # =
                        (.*)            # value
                        $/x ) {         # end of line
            my $error = "Not a valid keyword entry on line $line_num " .
                "in $defs_file: \'$line\'" ;
            push( @$self{ $ERRORS }, $error ) ;
            return(1) ;
        }
        my $keyword = $1 ;
        my $values  = $2 ;

        dprint( "defs: \'$keyword\' = \'$values\'" ) ;

        $keyword =~ s/\s+$// ;      # remove trailing whitespace
        $keyword =~ tr/A-Z/a-z/ ;   # make lower case

        $values  =~ s/^\s+// ;      # remove leading whitespace
        $values  =~ s/\s+$// ;      # remove trailing whitespace

        if ( $keyword eq 'keyword' ) {
            # See if a section name was given
            $current_section = $DEFS_ALL_SECTIONS ;     # default
            if ( $values =~ /^(.*)\:(.*)$/ ) {
                $current_section = $1 ;
                $current_keyword = $2 ;
            } else {
                $current_keyword = $values ;
            }

            # we'll want to check this later to see if the keyword is
            # defined.
            $self->{ $DEFS_KEYWORDS }->{ $current_section }->{ $current_keyword } = 1 ;

            dprint("defs: section=$current_section keyword=$current_keyword");

        } elsif ( $keyword eq 'type' ) {
            my $type = $values ;
            $type =~ tr/A-Z/a-z/ ;        # make lower case
            if ( not defined( $valid_types{ $type } )) {
                my $error = "Invalid type ($type) on line $line_num " .
                    "in $defs_file" ;
                push( @$self{ $ERRORS }, $error ) ;
                close $fd ;
                return(1) ;
            }

            $self->{ $DEFS_TYPES}->{ $current_section }->{ $current_keyword } = $type ;

        } elsif ( $keyword eq 'separator' ) {
            my $sep = $values ;
            # remove any surrounding balanced quotes
            $sep = $1 if ( $sep =~ /^\"(.*)\"$/ ) ;
            $sep = $1 if ( $sep =~ /^\'(.*)\'$/ ) ;

            $self->{ $DEFS_SEPARATOR }->{ $current_section }->{ $current_keyword } = $sep ;

        } elsif ( $keyword eq 'allowed-values' ) {

            # if the user escapes a comma or backslash to have it part
            # of the data, then hide it for now

            $values =~ s/\\,/$HIDE_SEPARATOR/eg ;
            $values =~ s/\\\\/$HIDE_BACKSLASH/eg ;

            my @values = split( /,/, $values ) ;
            foreach my $value ( @values ) {
                # put any separators back but without the backslash
                $value =~ s/$HIDE_SEPARATOR/,/g ;     

                # now put any dual backslashes back - but only one
                $value =~ s/$HIDE_BACKSLASH/\\/g ;     

                dprint( "Pushing ARRAY value \'$value\' to keyword \'$keyword\'" ) ;
                # create the empty anonymous array if it doesn't exist
                my $ref = $self->{ $DEFS_ALLOWED }->{ $current_section }->{ $current_keyword } ;
                if ( ! defined( $ref )) {
                    $self->{ $DEFS_ALLOWED }->{ $current_section }->{ $current_keyword } = [] ;
                }

                # get rid of whitespace
                $value =~ s/^\s+// ;
                $value =~ s/\s+$// ;

                # now strip any balanced quotes that were used to preserve whitespace

                $value = $1 if ( $value =~ /^\"(.*)\"$/ ) ;
                $value = $1 if ( $value =~ /^\'(.*)\'$/ ) ;

                # now save the value

                $ref = $self->{ $DEFS_ALLOWED }->{ $current_section }->{ $current_keyword } ;
                push( @{$ref}, $value ) ;
            }

        } else {
            my $error = "Not a valid keyword (\'$keyword\') on " .
                "line $line_num in $defs_file: \'$line\'" ;
            push( @$self{ $ERRORS }, $error ) ;
            return(1) ;
        }
        
    }

    return(0) ;
}


# internal non-OOP function to check if a value is allowed.
# allowed values are set in the optional definitions file.
#
# Inputs:
#       object instance
#       section name
#       keyword name
#       value to be tested
# Returns:
#       0 - ok - allowed
#       1 - not ok - not allowed

sub value_allowed {
    my $instance    = shift ;
    my $section     = shift ;
    my $keyword     = shift ;
    my $value       = shift ;

    my @refs = (
        $instance->{ $DEFS_ALLOWED }->{ $section }->{ $keyword },
        $instance->{ $DEFS_ALLOWED }->{ $DEFS_ALL_SECTIONS }->{ $keyword },
    ) ;

    foreach my $ref ( @refs ) {
        my $found = 0 ;
        if ( defined( $ref )) {
            foreach my $ok_value ( @$ref ) {
                if ( $value eq $ok_value ) {
                    $found++ ;
                    last ;
                }
            }
            return(0) if ( $found == 0 ) ;
        }
    }
    return(1) ;     # allowed
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
to a scalar value, an array of values, or an associative array of values.

Lines can be continued across multiple lines by ending a line with a
backslash.  Values are by default separated by commas.  To have a
separtator or a backslash as part of the data, escape them with a
backslash.

Other config files can be included, to any depth, via a #include line.

Comments begin with a '#' character (if it isn't a #include) and blank
lines are ignored.

To preserve whitespace around values, use matching single or double
quotes around a value.

A optional definitions file can be provided so that a different
separator than a comma can be given, restriction to a set of
allowed values, and provide the type of value there instead of in
the main config file.  These can be specified for a specific keyword
within a section, or globally to a keyword that may be present in
multiple sections.

If a definitions file is provided, then keywords cannot be in the
config file, unless they are defined in the definitions file.
Unless the option 'AcceptUndefinedKeywords' is provided and set
to 'yes'.  If there is no definitions file, it can be given as
a empty string or undefined value to Moxad::Config->new().
If a 'type' is provided in both the config file and the definitions
file for a section/keyword, then they must match.  One does not
over-ride the other.

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

=head1 Definitions file example

    # This keyword1 will only apply to section section-name1
    keyword                 = section-name1:keyword1
    type                    = array
    separator               = ;
    allowed-values          = val1, val2, val3 \
                              'val 4   '

    # this keyword2 will apply to all sections
    keyword                 = keyword2
    type                    = hash
    separator               = ,

=head1 Class methods

=head2 new

 my $cfg1 = Moxad::Config->new( $file, $defs_file, %options ) ;

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

=head2 errors

 my $num_errs = $cfg1->errors() ;
 my @errors   = $cfg1->errors() ;

=head2 clear_errors

 $cfg1->clear_errors() ;

=head2 reload

 $cfg1->reload() ;


=head1 Code sample

 #!/usr/bin/env perl
 
 use strict ;
 use warnings ;
 use Moxad::Config ;
 
 Moxad::Config->set_debug(0) ;  # off - default
 
 my $cfg1 = Moxad::Config->new(
    "test.conf",
    "test-defs.conf",
    { 'AcceptUndefinedKeywords' => 'yes' } ) ;
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
