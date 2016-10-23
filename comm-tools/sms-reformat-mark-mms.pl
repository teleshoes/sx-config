#!/usr/bin/perl
use strict;
use warnings;

sub main(@){

  my %mms;
  for my $line(`cat all_mms`){
    if($line !~ /^([0-9+]+),(\d+),(\d+),(S|M),(INC|OUT),(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),"(.*)"/mgi){
      die "malformed mms line: $line";
    }
    my ($num, $dateMillis, $dateSentMillis, $type, $dir, $dateFmt, $msg) = ($1, $2, $3, $4, $5, $6, $7);
    my $sex = int($dateMillis/1000);
    chomp $sex;
    my $minSex = $sex % (60*60);

    my $key = "$num-$dir-$minSex-$msg";
    if(not defined $mms{$key}){
      $mms{$key} = [];
    }
    push @{$mms{$key}}, {
      line => $line,
      num => $num,
      dir => $dir,
      msg => $msg,
      date => $dateFmt,
      sex => $sex,
      minSex => $minSex,
    };
  }

  for my $file(`ls *.sms`){
    chomp $file;
    next if -l $file;
    my $contents = `cat $file`;
    my $ok = {};
    my %lineNums;
    my $lineNum=1;
    my @goodLines;
    open FH, "< $file" or die "could not read $file\n$!\n";
    while(my $line = <FH>){
      if($line !~ /^([0-9+]+),(\d+),(\d+),(S|M),(INC|OUT),(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),"(.*)"$/i){
        die "malformed line: $line";
      }
      my ($num, $dateMillis, $dateSentMillis, $type, $dir, $dateFmt, $msg) = ($1, $2, $3, $4, $5, $6, $7);

      my $sex = int($dateMillis/1000);
      chomp $sex;
      my $minSex = $sex % (60*60);

      my $key = "$num-$dir-$minSex-$msg";
      my $matches = $mms{$key};
      if(defined $matches and @$matches > 0){
        for my $msg(@$matches){
          my $mmsMinSex = $$msg{minSex};
          my $diff = $minSex - $mmsMinSex;
          $diff = 0-$diff if $diff < 0;
          if($diff < 60*60*6){
            $type = "M";
            last;
          }else{
            die "NOTOK: $$msg{line}";
          }
        }
      }
      $line = "$num,$dateMillis,$dateSentMillis,$type,$dir,$dateFmt,\"$msg\"\n";
      push @goodLines, $line;
    }
    close FH;
    open FH, "> $file";
    for my $line(@goodLines){
      print FH $line;
    }
    close FH;
  }
}

&main(@ARGV);
