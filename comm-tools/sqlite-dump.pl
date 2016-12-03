#!/usr/bin/perl
use strict;
use warnings;

my $usage = "Usage:
  $0 SQLITE_DB OUTPUT_TXT_FILE
    dump SQLITE_DB to text with \"sqlite3 SQLITE_DB .dump\"
    write output to OUTPUT_TXT_FILE
";

sub main(@){
  die $usage if @_ != 2 or not -f $_[0];
  my ($db, $outFile) = @_;
  die "$outFile exists already\n" if -e $outFile;

  my @lines;

  open FH, "-|", "sqlite3", $db, ".dump"
    or die "could not run sqlite3\n$!\n";
  my @dumpLines = <FH>;
  @lines = (@lines, @dumpLines);
  close FH;
  die "error running sqlite3\n" if $? != 0;

  open FH, "> $outFile" or die "could not write $outFile\n$!\n";
  print FH @lines;
  close FH;
}

&main(@ARGV);
