#!/usr/bin/perl
use strict;
use warnings;

sub main(@){
  for my $file(`ls *.sms`){
    chomp $file;
    my $contents = `cat $file`;
    my $ok = {};
    while($contents =~ /^([0-9+]+),(\d+),(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),"((?:[^"\n]|""|\n)*)"/mgi){
      my ($num, $dir, $date, $msg) = ($1, $2, $3, $4);
      my $line = "$num,$dir,$date,\"$msg\"";

      my $sex = `date --date="$date" +%s`;
      chomp $sex;
      my $minSex = $sex % (60*60);

      my $key = "$num-$dir-$minSex-$msg";
      my $arr;
      if(defined $$ok{$key}){
        $arr = $$ok{$key};
      }else{
        $arr = [];
        $$ok{$key} = $arr;
      }
      push @$arr, {
        line => $line,
        num => $num,
        dir => $dir,
        msg => $msg,
        date => $date,
        sex => $sex,
        minSex => $minSex,
      };
    }
    my @goodEntries;
    for my $key(sort keys %$ok){
      my @entries = @{$$ok{$key}};
      my $goodEntry = undef;
      my $minSex = undef;
      my $maxSex = undef;
      for my $e(@entries){
        if(not defined $goodEntry or $$e{sex} < $$goodEntry{sex}){
          $goodEntry = $e;
        }
        if(not defined $minSex or $$e{sex} < $minSex){
          $minSex = $$e{sex};
        }
        if(not defined $maxSex or $$e{sex} > $maxSex){
          $maxSex = $$e{sex};
        }
      }
      if($maxSex - $minSex > 60*60*6){
        my $line = ${$entries[0]}{line};
        print STDERR "huge separation: $line\n";
      }
      push @goodEntries, $goodEntry;
    }
    @goodEntries = sort {$$a{sex} <=> $$b{sex} || $$a{dir} <=> $$b{dir}} @goodEntries;
    open FH, "> $file";
    for my $entry(@goodEntries){
      print FH "$$entry{line}\n";
    }
    close FH;
  }
}

&main(@ARGV);
