#!/usr/bin/perl -w

# Create matrix for smoke test results
# (c)'01 H.Merijn Brand [27 August 2001]
# modified bt Mattia Barbon for Parrot

# mkovz.pl [ e-mail [ folder ]]

use strict;

use vars qw($VERSION);
$VERSION = "0.01";

use Config;
my $email = shift || getpwuid $<;
my $testd = shift || "/usr/3gl/CPAN/perl-current";
my (%rpt, @confs, %confs, @manifest);

open RPT, "> $testd/mktest.rpt" or die "mktest.rpt: $!";
select RPT;

my $conf   = "";
my $debug  = "";
$rpt{patch} = "?";
my ($out, @out) = ("$testd/mktest.out", 1 .. 5);
open OUT, "<$out" or die "Can't open $out: $!";
for (<OUT>) {
    m/^\s*$/ and next;
    m/^-+$/  and next;

    # Buffer for broken lines (Win32, VMS)
    pop @out;
    unshift @out, $_;
    chomp $out[0];

    if (m/^\s*Smoking patch (.*)/) {
	$rpt{patch} = $1;
        $rpt{patch} =~ s/^\s*(.*?)\s*$/$1/;
	next;
	}
    if (m/^MANIFEST /) {
	push @manifest, $_;
	next;
	}
    if (s/^Configuration:\s*//) {
	# Unable to build in previous conf was hidden by crash junk?
	exists $rpt{$conf}{$debug}  or $rpt{$conf}{$debug}  = "-";

	s/-Dusedevel\s+//;
	$debug = s/--debugging\s*// ? "D" : "";
	s/\s+-des//;
	s/\s+$//;
	$conf = $_;
	$confs{$_}++ or push @confs, $conf;
	next;
	}
    if (m/^\s*All tests successful/) {
	$rpt{$conf}{$debug} = "O";
	next;
	}
    #XXX review this!
    if (m/DO NOT MATCH THIS^\s*Skipped this configuration/) {
	if ($^O =~ m/^(?: hpux | freebsd )$/x) {
	    (my $dup = $conf) =~ s/ -Duselongdouble//;
	    if (exists $rpt{$dup}{$debug}{stdio}) {
		@{$rpt{$conf}{$debug}} = @{$rpt{$dup}{$debug}};
		next;
		}
	    $dup =~ s/ -Dusemorebits/ -Duse64bitint/;
	    if (exists $rpt{$dup}{$debug}{stdio}) {
		@{$rpt{$conf}{$debug}}{qw(stdio perlio)} =
		    @{$rpt{$dup}{$debug}}{qw(stdio perlio)};
		next;
		}
	    $dup =~ s/ -Duse64bitall/ -Duse64bitint/;
	    if (exists $rpt{$dup}{$debug}{stdio}) {
		@{$rpt{$conf}{$debug}}{qw(stdio perlio)} =
		    @{$rpt{$dup}{$debug}}{qw(stdio perlio)};
		next;
		}
	    }
	$rpt{$conf}{$debug}{stdio}  = ".";
	$rpt{$conf}{$debug}{perlio} = ".";
	next;
	}
    if (m/^\s*Unable to (?=([cbmt]))(?:build|configure|make|test) perl/) {
	$rpt{$conf}{$debug}  = $1;
	$rpt{$conf}{$debug}  = $1;
	next;
	}
    # /Fix/ broken lines
    if (m/^\s*FAILED/ || m/^\s*DIED/) {
	foreach my $out (@out) {
	    $out =~ m/\.\./ or next;
	    push @{$rpt{$conf}{$debug}}, $out . substr $_, 3;
	    last;                
	    }
	next;
	}
    if (m/FAILED/) {
	ref $rpt{$conf}{$debug} or
	    $rpt{$conf}{$debug} = [];	# Clean up sparse garbage
	push @{$rpt{$conf}{$debug}}, $_;
	next;
	}
    }

my $ccv = $Config{ccversion}||$Config{gccversion};
print <<EOH;
Automated smoke report for patch $rpt{patch}
          v$VERSION         on $^O using $Config{cc} version $ccv
O = OK
F = Failure(s), extended report at the bottom
? = still running or test results not (yet) available
Build failures during:       - = unknown
    c = Configure, m = make, t = make test-prep

         Configuration
---  --------------------------------------------------------------------
EOH

my @fail;
for my $conf (@confs) {
    for my $debug ("", "D") {
        my $res = $rpt{$conf}{$debug};
        if (ref $res) {
            print "F ";
            my $s_conf = $conf;
            $debug and substr ($s_conf, 0, 0) = "--debugging ";
            push @fail, [ $s_conf, $res ];
            next;
        }
        print $res ? $res : "?", " ";
    }
    print " $conf\n";
}

print <<EOE;
| |
| +- --debugging
+--- normal
EOE

@fail and print "\nFailures:\n\n";
for my $i (0 .. $#fail) {
    my $ref = $fail[$i];
    printf "%-12s %s\n", $^O, @{$ref}[0];
    if ($i < $#fail) {	# More squeezing
	my $nref = $fail[$i + 1];
	"@{$ref->[-1]}" eq "@{$nref->[-1]}" and next;
	}
    print @{$ref->[-1]}, "\n";
    }

@manifest and print RPT "\n\n", @manifest;

close RPT;
select STDOUT;

my $mailer = "/usr/bin/mailx";
my $subject = "Parrot Smoke $rpt{patch} $Config{osname} $Config{osvers}";
if ($mailer =~ m/sendmail/) {
    local (*MAIL, *BODY, $/);
    open  BODY, "< $testd/mktest.rpt";
    open  MAIL, "| $mailer -i -t";
    print MAIL join "\n",
	"To: $email",
	"From: ...",
	"Subject: $subject",
	"",
	<BODY>;
    close BODY;
    close MAIL;
    }
elsif( $mailer =~ m/perl/i ) {
    my $mailhost = $ENV{MAILHOST};
    my $from = $ENV{SENDER};
    die "You must specify MAILHOST and SENDER if you use Net::SMTP"
        unless $from && $mailhost;
    require Net::SMTP;
    local *BODY;

    open  BODY, "< $testd/mktest.rpt";
    my $mail = new Net::SMTP( $mailhost );
    $mail->mail( $from );
    $mail->to( $email );
    $mail->data;
    $mail->datasend( "To: $email\n" );
    $mail->datasend( "From: $from\n" );
    $mail->datasend( "Subject: $subject\n" );
    $mail->datasend( "\n" );
    foreach my $i ( <BODY> ) { $mail->datasend( $i ) };
    $mail->dataend;
    $mail->quit;
    close BODY;
}
else {
    system "$mailer -s '$subject' $email < $testd/mktest.rpt";
    }
