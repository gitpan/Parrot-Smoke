#!/usr/bin/perl -w

# Smoke test for parrot
# (c) 2001 Mattia Barbon
# based upon the Smoke test for perl-current
# by H.Merijn Brand and Nicholas Clark

use strict;

sub usage ()
  {
    print STDERR "usage: mktest.pl [<smoke.cfg>]\n";
    exit 1;
  }                             # usage

@ARGV == 1 and $ARGV[0] eq "-?" || $ARGV[0] =~ m/^-+help$/ and usage;

use Config;
use Cwd;
use Getopt::Long;
use File::Find;

my $norun   = 0;
my $verbose = 0;
GetOptions (
            "n|norun|dry-run" => \$norun,
            "v|verbose:i"     => \$verbose, # NYI
           ) or usage;
my $config_file = shift || "smoke.cfg";

open TTY,    ">&STDERR";	select ((select (TTY),    $| = 1)[0]);
open STDERR, ">&1";		select ((select (STDERR), $| = 1)[0]);
open LOG,    "> mktest.out";	select ((select (LOG),    $| = 1)[0]);
select ((select (STDOUT), $| = 1)[0]);

# take values from environment
my $MAKE = $ENV{MAKE};
$MAKE = "$MAKE -E" if $MAKE eq 'dmake';
$MAKE = "$MAKE -a" if $MAKE eq 'nmake';

sub is_win32 { $^O eq 'MSWin32' }
# this kludge is an hopefully portable way of having
# redirections ( tested on Linux and Win2k )
sub run {
  my( $command, $sub, %redir ) = @_;
  my( $redir_string ) = '';

  defined $sub and
    return &$sub ($command);

  while ( my @dup = each %redir ) {
    my( $from, $to ) = @dup;
    if ( $to eq 'STDERR' ) {
      $to = "qq{>&STDERR}";
    } elsif ( $to eq 'STDOUT' ) {
      $to = "qq{>&STDOUT}";
    } elsif ( $to eq '/dev/null' ) {
      $to = ( $^O eq 'MSWin32' ) ?
        'qq{> NUL:}' : "qq{> $to}";
    } else {
      $to = "qq{> $to}";
    }

    $redir_string .= "open $from, $to;"
  }

  #print "$^X -e \"$redir_string;system q{$command};\"";
  system "$^X -e \"$redir_string;system q{$command};\"";
}

sub make 
  {
    my $cmd = shift;

    return run "$MAKE $cmd", undef, @_ ? @_ : ( 'STDOUT' => '/dev/null' );
  }                             #make

sub ttylog (@)
  {
    print TTY @_;
    print LOG @_;
  }                             # ttylog

my @config;
if (defined $config_file && -s $config_file) {
  open CONF, "< $config_file" or die "Can't open '$config_file': $!";
  my @conf;
  # Cheat. Force a break marker as a line after the last line.
  foreach (<CONF>, "=") {
    m/^#/ and next;
    s/\s+$// if m/\s/;          # Blanks, new-lines and carriage returns. M$

    if (!m/^=/) {
      # Not a break marker
      push @conf, $_;
      next;
    }

    # Break marker, so process the lines we have.
    my %conf = map { $_ => 1 } @conf;
    if (keys %conf == 1 and exists $conf{""} ) {
      # There are only blank lines - treat it as if there were no lines
      # (Lets people have blank sections in configuration files without
      #  warnings.)
      # Unless there is a policy target.  (substituting ''  in place of
      # target is a valid thing to do.)
      @conf = ();
    }
    next unless @conf;

    while (my ($key, $val) = each %conf) {
      $val > 1 and warn "Configuration line '$key' duplicated $val times";
    }
    my $args = [@conf];
    @conf = ();

    push @config, $args;
  }
} else {
  die "No default configuration available, please specify one!";

  @config = (
             [ "",
               "-Dusethreads -Duseithreads"
             ],
             [ "-Uuseperlio",
               "-Duseperlio",
               "-Duseperlio -Duse64bitint",
               "-Duseperlio -Duse64bitall",
               "-Duseperlio -Duselongdouble",
               "-Duseperlio -Dusemorebits",
               "-Duseperlio -Duse64bitall -Duselongdouble"
             ],
             [ "", "-Duselongdouble"
             ],
             { policy_target =>       "-DDEBUGGING",
               args          => [ "", "-DDEBUGGING" ]
             },
            );
}

my $testdir = getcwd;

my $patch = 'unknown';
if (open OK, "<.timestamp") {
    <OK>;
    my $stamp = <OK>;
    chomp $stamp;
    $stamp =~ s/^\w+\s//;
    $patch = $stamp;
    close OK;
    print LOG "Smoking patch $patch\n\n";
}

#XXX
=head1 BETTER MANIFEST CHECK!!!!
  if (open MANIFEST, "< MANIFEST") {
    # I've done no tests yet, and I've been started after the rsync --delete
    # Now check if I'm in sync
    my %MANIFEST = ( ".patch" => 1, map { s/\s.*//s; $_ => 1 } <MANIFEST>);
    find (sub {
            -d and return;
            m/^mktest\.(log|out)$/ and return;
            my $f = $File::Find::name;
            $f =~ s:^$testdir/?::;
            if (exists $MANIFEST{$f}) {
              delete $MANIFEST{$f};
              return;
	    }
            $MANIFEST{$f} = 0;
          }, $testdir);
    foreach my $f (sort keys %MANIFEST) {
      ttylog "MANIFEST ",
        ($MANIFEST{$f} ? "still has" : "did not declare"), " $f\n";
    }
  }
=cut

  my @p_conf = ("", "");

run_tests (\@p_conf, "--defaults", [], @config);

close LOG;

sub run_tests {
  my ($p_conf, $old_config_args, $substs, $this_test, @tests) = @_;

  # $this_test is either
  # [ "", "-Dthing" ]
  # since we don't have policy substitution

  foreach my $conf (@$this_test) {
    my $config_args = $old_config_args;
    # Try not to add spurious spaces as it confuses mkovz.pl
    length $conf and $config_args .= " $conf";
    my @substs = @$substs;

    if (@tests) {
      # Another level of tests
      run_tests ($p_conf, $config_args, \@substs, @tests);
      next;
    }

    # No more levels to expand
    my $s_conf = join "\n" => "", "Configuration: $config_args",
      "-" x 78, "";
    ttylog $s_conf;

    # You can put some optimizations (skipping configurations) here
    #if ( $^O =~ m/^(?: hpux | freebsd )$/x &&
    #     $conf =~ m/longdouble|morebits/) {
    # longdouble is turned off in Configure for hpux, and since
    # morebits is the same as 64bitint + longdouble, these have
    # already been tested. FreeBSD does not support longdoubles
    # well enough for perl (eg no sqrtl)
    #   ttylog " Skipped this configuration for this OS (duplicate test)\n";
    #   next;
    #    }

    print TTY "Make distclean ...";
    make( "-i distclean", 'STDERR' => '/dev/null' );
    run "unlink Makefile", sub { unlink 'Makefile' };

    print TTY "\nConfigure ...";
    run "$^X Configure.pl $config_args", undef, 'STDOUT' => '/dev/null';

    unless ($norun or (-f "Makefile")) {
      ttylog " Unable to configure Parrot in this configuration\n";
      next;
    }

    print TTY "\nMake ...";
    make " ";

    my $parrot = "test_prog$Config{exe_ext}";
    unless ($norun or (-s $parrot && -x _)) {
      ttylog " Unable to make Parrot in this configuration\n";
      next;
    }

    print TTY "\n Tests start here:\n";

    if ($norun) {
      ttylog "\n";
      next;
    }

    open TST, "$MAKE test |";

    my @nok = ();
    select ((select (TST), $| = 1)[0]);
    #XXX probably more than necessary, but it does not hurt
    while (<TST>) {
      # Still to be extended
      m,^ *$, ||
      m,^	AutoSplitting, ||
      m,^\./miniperl , ||
      m,^autosplit_lib, ||
      m,^	Making , ||
      m,^make\[[12], ||
      m,make( TEST_ARGS=)? (_test|TESTFILE=), ||
      m,^\s+make\s+lib/, ||
      m,^ *cd t &&, ||
      m,^if \(true, ||
      m,^else \\, ||
      m,^fi$, ||
      m,^lib/ftmp-security....File::Temp::_gettemp: Parent directory \((\.|/tmp/)\) is not safe, ||
      m,^File::Temp::_gettemp: Parent directory \((\.|/tmp/)\) is not safe, ||
      m,^ok$, ||
      m,^[-a-zA-Z0-9_/]+\.*(ok|skipping test on this platform)$, ||
      m,^(xlc|cc_r) -c , ||
      m,^\s+$testdir/, ||
      m,^sh mv-if-diff\b, ||
      m,File \S+ not changed, ||
      # Don't know why BSD's make does this
      m,^Extracting .*with variable substitutions, ||
      # Or these
      m,cc\s+-o\s+perl.*perlmain.o\s+lib/auto/DynaLoader/DynaLoader\.a\s+libperl\.a, ||
      m,^\S+ is up to date, ||
      m,^   ### , and next;
      if (m/^u=.*tests=/) {
        s/(\d\.\d*) /sprintf "%.2f ", $1/ge;
        print LOG;
      } else {
        push @nok, $_;
      }
      print;
    }
    print LOG map { "    $_" } @nok;
    if (grep m/^All tests successful/, @nok) {
      print TTY "\nOK, archive results ...";
    } else {
      my @harness;
      for (@nok) {
      m:^(\w+/[-\w/]+).*: or next;
        # Remeber, we chdir into t, so -f is false for op/*.t etc
        push @harness, (-f "$1.t") ? "$1.t" : "gack!!!";
      }
      if (@harness) {
        print TTY "\nExtending failures with Harness\n";
        push @nok, "\n",
          grep !m:\bFAILED tests\b: &&
            !m:% okay$: => run "$^X t/harness @harness";
      }
    }
    print TTY "\n";
  }
}

__END__
