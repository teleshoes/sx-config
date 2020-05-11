#!/usr/bin/perl
use strict;
use warnings;

sub getContactSortKey($);
sub parseLinesToContacts(@);

my $usage = "Usage:
  $0 INPUT_VCF_FILE OUTPUT_VCF_FILE
    sort contacts in vcf file, and cleanup each vcard a bit
";

sub main(@){
  my ($inputVCF, $outputVCF);
  if(@_ == 2){
    ($inputVCF, $outputVCF) = @_;
  }else{
    die $usage;
  }
  die "$usage\nERROR: $inputVCF is not a file\n" if not -f $inputVCF;
  die "$usage\nERROR: $outputVCF exists already\n" if -e $outputVCF;

  my @lines = `cat $inputVCF`;

  @lines = map {$_ =~ s/^(PHOTO);(ENCODING=b);(TYPE=JPEG):/$1;$3;$2:/; $_} @lines;
  @lines = map {$_ =~ s/[\r\n]*$/\n/; $_} @lines;
  @lines = grep {$_ !~ /^REV:\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ$/} @lines;

  my @contacts = parseLinesToContacts(@lines);

  my %contactsByKey = map {getContactSortKey($_) => $_} @contacts;

  @contacts = map {$contactsByKey{$_}} sort keys %contactsByKey;

  open FH, "> $outputVCF" or die "ERROR: could not write $outputVCF\n$!\n";
  print FH $_ foreach @contacts;
  close FH;
}

sub getContactSortKey($){
  my ($contact) = @_;
  my ($first, $last, $other, $fullName, $num);
  if($contact =~ /^FN:(.+)$/m){
    $fullName = $1;
  }
  my $segRe = '(?:[^;\\\\]|\\\\;)*';
  if($contact =~ /^N:($segRe);($segRe);(.*)/m){
    ($last, $first, $other) = ($1, $2, $3);
  }
  if($contact =~ /^TEL.*(\d+)/m){
    $num = $1;
  }

  my $name;
  if(defined $fullName){
    $name = $fullName;
  }elsif(defined $first and defined $last){
    $name = "$first $last";
  }elsif(defined $first){
    $name = $first;
  }elsif(defined $last){
    $name = $last;
  }elsif(defined $other){
    $name = $other;
  }else{
    $name = "unknown";
  }
  $name =~ s/^\s*//;
  $name = lc $name;

  $num = "" if not defined $num;

  return "$name|$num|$contact";
}

sub parseLinesToContacts(@){
  my @lines = @_;

  my @contacts;
  my $cur = undef;
  for my $line(@lines){
    $cur = '' if not defined $cur;
    $cur .= $line;
    if($line =~ /END:VCARD\s*$/){
      push @contacts, $cur;
      $cur = undef;
    }
  }
  push @contacts, $cur if defined $cur;

  return @contacts;
}

&main(@ARGV);
