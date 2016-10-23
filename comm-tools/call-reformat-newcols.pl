#!/usr/bin/perl
use strict;
use warnings;

my $REPO_DIR = "$ENV{HOME}/Code/s5/backup/backup-call/repo";

sub undo();

sub main(@){
  chdir $REPO_DIR;
  $ENV{PWD} = $REPO_DIR;

  if(@_ > 0 and $_[0] =~ /undo/){
    undo();
    exit;
  }
  for my $file(`ls *.call`){
    chomp $file;
    next if -l $file;
    open FH, "< $file";
    my @lines = <FH>;
    close FH;

    my $ringPath = '/org/freedesktop/Telepathy/Account/ring/tel/ring';
    my $dateRe = '\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d';
    open FH, "> $file";
    for my $oldLine(@lines){
      chomp $oldLine;
      if($oldLine !~ /^$ringPath,\s*([0-9+]+),(\d+),($dateRe),($dateRe)$/){
        die "invalid line: $oldLine\n";
      }
      my ($num, $dir, $dateStart, $dateEnd) = ($1, $2, $3, $4);
      my $newDir;
      if($dir == 1){
        $newDir = "INC";
      }elsif($dir == 0){
        $newDir = "OUT";
      }elsif($dir == 2){
        $newDir = "MIS";
      }else{
        die "INVALID DIR: $dir ($oldLine)\n";
      }

      my $sex = `date --date "$dateStart" +%s`;
      chomp $sex;
      die "invalid date: $oldLine\n" if $sex !~ /^\d+$/;
      my $millisex = $sex . "000";

      my $dateEndSex = `date --date "$dateEnd" +%s`;
      my $durSex = $dateEndSex - $sex;
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
      print STDERR "$durSex  $durFmt\n" if $isNeg;

      my $newDate = `date --date \@$sex +'%Y-%m-%d %H:%M:%S'`;
      chomp $newDate;
      die "DATE ERROR: ($dateStart != $newDate) $oldLine\n" if $dateStart ne $newDate;

      my $newLine = "$num,$millisex,$newDir,$newDate,$durFmt\n";
      print FH $newLine;
    }
    close FH;
  }
}

sub undo(){
  for my $file(`ls *.call`){
    chomp $file;
    next if -l $file;
    open FH, "< $file";
    my @lines = <FH>;
    close FH;

    my $ringPath = '/org/freedesktop/Telepathy/Account/ring/tel/ring';
    my $dateRe = '\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d';
    open FH, "> $file";
    for my $oldLine(@lines){
      chomp $oldLine;
      if($oldLine !~ /^([0-9+]+),(\d+),(INC|OUT|MIS),($dateRe),\s*(-?)(\d+)h\s*(\d+)m\s(\d+)s$/){
        die "invalid line: $oldLine\n";
      }
      my ($num, $dateMillis, $dir, $date, $durSign, $durH, $durM, $durS) =
        ($1, $2, $3, $4, $5, $6, $7, $8);
      my $oldDir;
      if($dir eq "INC"){
        $oldDir = 1;
      }elsif($dir eq "OUT"){
        $oldDir = 0;
      }elsif($dir eq "MIS"){
        $oldDir = 2;
      }else{
        die "INVALID DIR: $dir ($oldLine)\n";
      }

      my $sex = `date --date "$date" +%s`;
      chomp $sex;
      die "invalid date: $oldLine\n" if $sex !~ /^\d+$/;
      my $millisex = $sex . "000";
      die "milli mismatch\n" if $millisex != $dateMillis;

      my $durSex = $durH*60*60 + $durM*60 + $durS;

      my $endMillis;
      if($durSign =~ /-/){
        $endMillis = $millisex - ($durSex*1000);
      }else{
        $endMillis = $millisex + ($durSex*1000);
      }

      my $dateStartCmd = "date --date=\@" . int($millisex/1000) . " +'%Y-%m-%d %H:%M:%S'";
      my $dateStartFmt = `$dateStartCmd`;
      chomp $dateStartFmt;
      die "fmt mismatch\n" if $dateStartFmt ne $date;

      my $dateEndCmd = "date --date=\@" . int($endMillis/1000) . " +'%Y-%m-%d %H:%M:%S'";
      my $dateEndFmt = `$dateEndCmd`;
      chomp $dateEndFmt;

      my $newLine = "$ringPath, $num,$oldDir,$dateStartFmt,$dateEndFmt\n";
      print FH $newLine;
    }
    close FH;
  }
}

&main(@ARGV);
