#!/usr/bin/perl
use strict;
use warnings;

sub main(@){
  for my $file(`ls *.call`){
    chomp $file;
    next if -l $file;
    my $contents = `cat $file`;
    my $ok = {};
    my %lineNums;
    my $lineNum=1;
    my $dateRe = '\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d';
    while($contents =~ /^([^,]+),\s*([0-9+]+),(\d+),($dateRe),($dateRe)$/mgi){
      my ($path, $num, $dir, $startDate, $endDate) = ($1, $2, $3, $4, $5);
      my $line = "$path, $num,$dir,$startDate,$endDate";

      my $startSex = `date --date="$startDate" +%s`;
      chomp $startSex;
      my $endSex = `date --date="$endDate" +%s`;
      chomp $endSex;
      my $dur = $endSex - $startSex;

      my $minSex = $startSex % (60*60);

      my $key = "$num-$dir-$minSex-$dur";
      my $arr;
      if(defined $$ok{$key}){
        $arr = $$ok{$key};
      }else{
        $arr = [];
        $$ok{$key} = $arr;
      }
      $lineNums{$line} = $lineNum++;
      push @$arr, {
        line => $line,
        num => $num,
        dir => $dir,
        dur => $dur,
        startDate => $startDate,
        endDate => $endDate,
        sex => $startSex,
        minSex => $minSex,
      };
    }
    my @goodEntries;
    for my $key(sort keys %$ok){
      my @entries = @{$$ok{$key}};
      my @buckets;
      for my $e(@entries){
        my $bucket = undef;
        for my $b(@buckets){
          my $isOk = 1;
          for my $bucketEntry(@$b){
            my $sexDiff = $$e{sex} - $$bucketEntry{sex};
            $sexDiff = 0-$sexDiff if $sexDiff < 0;
            if($sexDiff > 60*60*6){
              $isOk = 0;
              last;
            }
          }
          if($isOk){
            $bucket = $b;
            last;
          }
        }
        if(not defined $bucket){
          $bucket = [];
          push @buckets, $bucket;
        }
        push @$bucket, $e;
      }
      if(@buckets > 1){
        print STDERR "warn: lotta buckets ${${$buckets[0]}[0]}{line}\n";
      }
      for my $bucket(@buckets){
        my @sortedEntries = sort {$$a{sex} <=> $$b{sex}} @$bucket;
        my $firstEntry = $sortedEntries[0];
        push @goodEntries, $firstEntry;
      }
    }
    my @goodLines = map {$$_{line}} @goodEntries;
    @goodLines = sort {$lineNums{$a} <=> $lineNums{$b}} @goodLines;
    open FH, "> $file";
    print FH "$_\n" foreach @goodLines;
    close FH;
  }
}

&main(@ARGV);
