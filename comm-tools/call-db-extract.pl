#!/usr/bin/perl
use strict;
use warnings;

sub main(@){
  my $db = shift;
  my @cmd;
  push @cmd, "sqlite3";
  push @cmd, $db;
  push @cmd, ".mode tcl";
  push @cmd, ""
    . " select"
    . "   remoteUid,"
    . "   startTime,"
    . "   endTime,"
    . "   isMissedCall,"
    . "   direction,"
    . "   headers"
    . " from events"
    . " where type = 3"
    . " order by id"
    ;
  open FH, "-|", @cmd;
  my @tclLines = <FH>;
  close FH;
  for my $line(@tclLines){
    if($line !~ /^"([0-9 ()\-\+\*#]*)"\s*"(\d+)"\s*"(\d+)"\s*"(\d+)"\s*"(\d+)"\s*"(\w*)"$/){
      die "invalid call db row: $line";
    }
    my ($number, $startDateSex, $endDateSex, $isMissed, $dir, $headers) = ($1, $2, $3, $4, $5, $6);
    my $dirFmt;
    if($headers eq "rejected"){ #hack
      $dirFmt = "REJ";
    }elsif($isMissed == 1){
      $dirFmt = "MIS";
    }elsif($dir == 2){
      $dirFmt = "OUT";
    }elsif($dir == 1){
      $dirFmt = "INC";
    }else{
      die "invalid call type: $line";
    }

    #remove everything but digits, +, *, and #
    $number =~ s/[^0-9+*#]//g;
    #remove US country code (remove leading + and/or 1 if followed by 10 digits)
    $number =~ s/^\+?1?(\d{10})$/$1/;

    my $dateMillisex = $startDateSex * 1000;

    my $sex = $startDateSex;
    my $dateFmt = `date --date \@$sex +'%Y-%m-%d %H:%M:%S'`;
    chomp $dateFmt;

    my $durSex = $endDateSex - $startDateSex;

    my $isNeg = 0;
    if($durSex < 0){
      $isNeg = 1;
      $durSex = 0-$durSex;
    }
    my $h = int($durSex / 60 / 60);
    my $m = int($durSex / 60) % 60;
    my $s = int($durSex) % 60;
    my $durFmt;
    if($isNeg){
      $durFmt = sprintf "-%01dh %02dm %02ds", $h, $m, $s;
    }else{
      $durFmt = sprintf " %01dh %02dm %02ds", $h, $m, $s;
    }

    print "$number,$dateMillisex,$dirFmt,$dateFmt,$durFmt\n";
  }
}

&main(@ARGV);
