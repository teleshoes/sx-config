#!/usr/bin/perl
use strict;
use warnings;

my $REPO_DIR = "$ENV{HOME}/Code/s5/backup/backup-sms/repo";

sub main(@){
  chdir $REPO_DIR;
  $ENV{PWD} = $REPO_DIR;

  for my $file(`ls *.sms`){
    chomp $file;
    next if -l $file;
    open FH, "< $file";
    my @lines = <FH>;
    close FH;

    open FH, "> $file";
    for my $oldLine(@lines){
      chomp $oldLine;
      if($oldLine !~ /^([0-9+]+),(\d+),(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),"(.*)"$/){
        die "invalid line: $oldLine\n";
      }
      my ($num, $dir, $date, $msg) = ($1, $2, $3, $4);
      my $newDir;
      if($dir == 1){
        $newDir = "INC";
      }elsif($dir == 2){
        $newDir = "OUT";
      }elsif($dir == 3){
        $newDir = "MIS";
      }else{
        die "INVALID DIR: $dir ($oldLine)\n";
      }

      my $sex = `date --date "$date" +%s`;
      chomp $sex;
      die "invalid date: $oldLine\n" if $sex !~ /^\d+$/;
      my $millisex = $sex . "000";

      my $newDate = `date --date \@$sex +'%Y-%m-%d %H:%M:%S'`;
      chomp $newDate;
      die "DATE ERROR: ($date != $newDate) $oldLine\n" if $date ne $newDate;

      my $sentMillisex = $millisex;

      my $newLine = "$num,$millisex,$sentMillisex,S,$newDir,$newDate,\"$msg\"\n";
      print FH $newLine;
    }
    close FH;
  }
}

&main(@ARGV);
