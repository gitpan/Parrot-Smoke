#!/usr/bin/perl -w

use FindBin;
use File::Spec;

my $PC = shift || 'C:\parrot-smoke';
my $CF = shift || 'smoke.cfg';
my $MAKE = 'nmake';
# not yet used
my $MAILHOST = 'smtp.nowhere.far';
my $MAIL_FROM = 'me@nowhere.far';

my $mktest = File::Spec->catfile( $FindBin::RealBin, 'mktest.pl' );
my $mkovz = File::Spec->catfile( $FindBin::RealBin, 'mkovz.pl' );
my $cfg = -f $CF ? $CF : File::Spec->catfile( $FindBin::RealBin, $CF );

chdir $PC or die "chdir '$PC' failed!";

$ENV{MAKE} = $MAKE;
$ENV{MAILHOST} = $MAILHOST;
$ENV{SENDER} = $MAIL_FROM;

qx{$^X -e "open STDERR,'>&STDOUT';system '$MAKE distclean'"};

qx{rsync --delete -avz cvs.perl.org::parrot-HEAD .};

system qq{$^X -e "open STDERR,'>&STDOUT';system '$^X $mktest $cfg';" > mktest.log};

system qq{$^X $mkovz smokers-reports\@perl.org $PC};
