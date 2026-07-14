#!/usr/bin/perl

# This is a multifile protocol dependency generator, requiring RPM 4.20.
# https://rpm.org/docs/latest/man/rpm-dependency-generators.7#Protocols
#
# When passed Perl files, it acts as a wrapper around the usual
# dependency generators, to:
# - Mark bundled libraries Provides with bundled().
# - Exclude Requires on things provided by a bundled library.
#
# It can also be passed the modules.conf file included with Lyrion Music
# Server, the format of which is effectively defined by function
# Slim::bootstrap::check_valid_versions.

use v5.40;

my $type = shift @ARGV;

my %macros;
open(
    my $rpm, '-|', 'rpm', map {('--eval' => "$_ %$_")}
    '__perllib_provides',
    '__perllib_requires',
    '_datadir',
);
while ( defined(my $line = <$rpm>) ) {
    $line =~ m/^(\S+) (.+)/ or die 'Could not expand RPM macros';
    $macros{$1} = $2;
}
close $rpm
    or warn "Error on closing rpm: $!";

my $cpan_lib_dir = $macros{_datadir}. '/lyrionmusicserver/CPAN/';
my $bundled_lib_dir = $macros{_datadir}. '/lyrionmusicserver/lib/';

if ( $type eq '--provides' ) {
    while ( defined(my $filename = <>) ) {
        chomp $filename;

        if ( $filename =~ m{/modules\.conf$} ) {
            say ';'. $filename;
            next;
        }

        open(my $perl_prov, '-|', $macros{__perllib_provides}, $filename)
            or next;

        say ';'. $filename;

        if (
            $filename =~ m{
                              ^
                              \Q$ENV{RPM_BUILD_ROOT}\E
                              (?:
                                  \Q$cpan_lib_dir\E |
                                  \Q$bundled_lib_dir\E
                              )
                      }xo
        ) {
            while ( defined(my $line = <$perl_prov> ) ) {
                $line =~ s/perl\((.+)\)/bundled(perl($1))/;
                print $line;
            }
        }
        else {
            while ( defined(my $line = <$perl_prov> ) ) {
                print $line;
            }
        }

        close $perl_prov
            or warn "Error on closing $macros{__perllib_provides}: $!";
    }
}
elsif ( $type eq '--requires' ) {
    while ( defined(my $filename = <>) ) {
        chomp $filename;

        if ( $filename =~ m{/modules\.conf$} ) {
            open my $modules_conf, '<', $filename
                or die "Could not open $filename: $!";

            say ";$filename";

            while ( defined(my $line = <$modules_conf>) ) {
                next unless $line =~ m/^\w/;
                my ($module, $min, $max) = split /\s+/, $line;

                unless ( is_bundled_module($module) ) {
                    if ( defined($min) ) {
                        say "perl($module) >= $min";
                    }
                    if ( defined($max) and $max =~ m/\d+\.(\d+)$/ ) {
                        my $strictly_max = $max + 10 ** (-1 * length($1));
                        say "perl($module) < $strictly_max";
                    }
                }
            }

            close $modules_conf
                or warn "Error on closing $filename: $!";

            next;
        }

        open(my $perl_req, '-|', $macros{__perllib_requires}, $filename)
            or next;

        say ';'. $filename;

        while ( defined(my $line = <$perl_req> ) ) {
            if ( $line =~ m/^perl\((.+)\)/ ) {
                print $line unless is_bundled_module($1);
            }
            else {
                print $line;
            }
        }

        close $perl_req
            or warn "Error on closing $macros{__perllib_requires}: $!";
    }
}
else {
    die "Unknown/unimplemented dependency type: $type";
}

sub is_bundled_module ($module) {
    $module =~ s{::}{/}g;
    $module .= '.pm';

    return(
        -f $ENV{RPM_BUILD_ROOT}. $cpan_lib_dir. $module
        or -f $ENV{RPM_BUILD_ROOT}. $bundled_lib_dir. $module
    );
}
