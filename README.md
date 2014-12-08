# Read config file(s) with Perl module

## Description
This module is a set of OOP methods to read a config file and provide access
to its sections, keywords and values.  A section is a grouping of keyword =
values.  A section begins at the beginning of a line and the keywords for that
section are indented.  A keyword can point to a scalar value, an array of
values, or a associative array of values.

Lines can be continued across multiple lines by ending a line with a
backslash.  Values are separated by commas.  To have a comma or a backslash as
part of the data, escape them with a backslash.

Other config files can be included, to any depth, via a #include line.

Comments begin with a '#' character (if it isn't a #include) and blank lines
are ignored.

To preserve whitespace around values, use matching single or double quotes
around a value.

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
