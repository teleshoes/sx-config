#!/usr/bin/perl
use strict;
use warnings;

my $REPO_DIR = "$ENV{HOME}/Code/s5/backup/backup-sms/repo";

sub main(@){
  chdir $REPO_DIR;
  $ENV{PWD} = $REPO_DIR;

  #for x in [0-9+]*.sms; do cat $x | LC_ALL=C sort > $x.new; mv $x.new $x; done

  for my $file(`ls *.sms`){
    chomp $file;
    next if -l $file;
    my %lines;
    open FH, "< $file" or die "could not read $file\n$!\n";
    while(my $line = <FH>){
      if($line !~ /^([0-9+]+),(\d+),(\d+),(S|M),(INC|OUT),(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),"(.*)"$/i){
        die "malformed line: $line";
      }
      my ($num, $dateMillis, $dateSentMillis, $type, $dir, $dateFmt, $msg) = ($1, $2, $3, $4, $5, $6, $7);

      #$type = "";

      #$dir = $dir eq "OUT" ? 1 : 2;

      #$dateSentMillis = 0;

      #$dateMillis = sprintf "%020d", $dateMillis;
      #$dateSentMillis = sprintf "%020d", $dateMillis;

      my $sortKey = "$num-$dateMillis-$dateSentMillis-$type-$dir-$msg";
      die "DUPE LINE: $line" if defined $lines{$sortKey};
      $lines{$sortKey} = $line;
    }
    close FH;
    open FH, "> $file";
    for my $sortKey(sort keys %lines){
      print FH $lines{$sortKey};
    }
    close FH;
  }
}

&main(@ARGV);
