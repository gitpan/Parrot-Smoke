#!/usr/bin/perl -w

use FindBin;
use File::Spec;

my $PC = shift || '/usr/CPAN/parrot-current';
my $CF = shift || 'smoke.cfg';
my $MAKE = "make";
my $MAILER = "mailx";
# used only if MAILER eq 'perl'
my $MAIL_HOST = "mailhost";
my $MAIL_FROM = "mailfrom";

my $mktest = File::Spec->catfile( $FindBin::RealBin, 'mktest.pl' );
my $mkovz = File::Spec->catfile( $FindBin::RealBin, 'mkovz.pl' );
my $cfg = -f $CF ? $CF : File::Spec->catfile( $FindBin::RealBin, $CF );

chdir $PC or die "chdir '$PC' failed!";

$ENV{MAKE} = $MAKE;
$ENV{MAILER} = $MAILER;
$ENV{MAILHOST} = $MAIL_HOST;
$ENV{SENDER} = $MAIL_FROM;

qx{$^X -e "open STDERR,'>&STDOUT';system '$MAKE distclean'"};

qx{rsync --delete -avz cvs.perl.org::parrot-HEAD .};

system qq{$^X -e "open STDERR,'>&STDOUT';system '$^X $mktest $cfg';" > mktest.log};

system qq{$^X $mkovz perl6-internals\@perl.org $PC};
