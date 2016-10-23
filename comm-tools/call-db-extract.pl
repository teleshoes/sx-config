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
    . "   number,"
    . "   date,"
    . "   duration,"
    . "   type"
    . " from calls"
    . " order by _id"
    ;
  open FH, "-|", @cmd;
  my @tclLines = <FH>;
  close FH;
  for my $line(@tclLines){
    if($line !~ /^"([0-9 ()\-\+]+)"\s*"(\d+)"\s*"(\d+)"\s*"(\d+)"$/){
      die "invalid SMS row: $line";
    }
    my ($number, $dateMillisex, $durSex, $type) = ($1, $2, $3, $4, $5);
    my $dir;
    if($type == 2){
      $dir = "OUT";
    }elsif($type == 1){
      $dir = "INC";
    }elsif($type == 3){
      $dir = "MIS";
    }else{
      die "invalid call type: $line";
    }

    #remove everything but digits and +
    $number =~ s/[^0-9+]//g;
    #remove US country code (remove leading + and/or 1 if followed by 10 digits)
    $number =~ s/^\+?1?(\d{10})$/$1/;

    my $sex = int($dateMillisex/1000);
    my $dateFmt = `date --date \@$sex +'%Y-%m-%d %H:%M:%S'`;
    chomp $dateFmt;

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

    print "$number,$dateMillisex,$dir,$dateFmt,$durFmt\n";
  }
}

&main(@ARGV);
