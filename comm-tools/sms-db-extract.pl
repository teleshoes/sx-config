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
    . "   address,"
    . "   date,"
    . "   date_sent,"
    . "   type,"
    . "   body"
    . " from sms"
    . " order by _id"
    ;
  open FH, "-|", @cmd;
  my @tclLines = <FH>;
  close FH;
  for my $line(@tclLines){
    if($line !~ /^"([0-9 ()\-\+]+)"\s*"(\d+)"\s*"(\d+)"\s*"(\d+)"\s*"(.*)"$/){
      die "invalid SMS row: $line";
    }
    my ($address, $dateMillisex, $dateSentMillisex, $type, $body) = ($1, $2, $3, $4, $5);
    my $dir;
    if($type == 2){
      $dir = "OUT";
    }elsif($type == 1){
      $dir = "INC";
    }else{
      die "invalid SMS type: $line";
    }
    my $number = $address;
    #remove everything but digits and +
    $number =~ s/[^0-9+]//g;
    #remove US country code (remove leading + and/or 1 if followed by 10 digits)
    $number =~ s/^\+?1?(\d{10})$/$1/;

    $dateSentMillisex = $dateMillisex if $dateSentMillisex == 0;

    my $sex = int($dateMillisex/1000);
    my $dateFmt = `date --date \@$sex +'%Y-%m-%d %H:%M:%S'`;
    chomp $dateFmt;

    $body =~ s/\r/\\r/g;

    print "$number,$dateMillisex,$dateSentMillisex,S,$dir,$dateFmt,\"$body\"\n";
  }
}

&main(@ARGV);
