#!/usr/bin/perl
use strict;
use warnings;

sub main(@){
  system "echo 2 > /sys/module/bcmdhd/parameters/op_mode";
  print "turn off tethering, turn off wifi, turn on tethering\n";
  print "ready?";
  <STDIN>;
  system "ip link set dev wlan0 master tether";
  print "tethering should now work\n";
  print "disable tethering? [Y/n] ";
  my $ok = <STDIN>;
  if($ok !~ /n/i){
    system "echo 1 > /sys/module/bcmdhd/parameters/op_mode";
    print "turn off tethering, turn off wifi, turn on wifi\n";
    print "also, have fun entering the wifi password\n";
  }else{
    print "ok, leaving tethering on. wifi wont work. rerun this to fix\n";
  }
  print "exiting, ok? (you might want to just close the terminal) ";
  <STDIN>;
}

&main(@ARGV);
