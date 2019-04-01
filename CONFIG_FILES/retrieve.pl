#!/usr/bin/perl
use strict;
use warnings;

my $ipmagicName = "sx";

my $host = `ipmagic $ipmagicName`;
my $user = "root";

sub main(@){
  die "Usage: $0 path [path path ..]\n" if @_ == 0 or $_[0] =~ /^(-h|--help)$/;
  chomp $host;
  for my $file(@_){

    #unboing file arguments if not already unboing-ed
    if($file =~ /^%/){
      $file = `unboing $file`;
      chomp $file;
    }
    if($file !~ /^\//){
      die "ERROR: files must be absolute paths: $file\n";
    }

    my $boing = `boing $file`;
    chomp $boing;
    print "$file => $boing\n";
    system "rsync", "-avP", "$user\@$host:$file", $boing;
  }
}

&main(@ARGV);
