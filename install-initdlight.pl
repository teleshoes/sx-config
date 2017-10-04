#!/usr/bin/perl
use strict;
use warnings;

sub run(@);

sub main(@){
  chdir "$ENV{HOME}/Code/s5/apks";
  run "adb", "uninstall", "x1125io.initdlight";
  run "adb", "install", "initdlight.apk";
  chdir "..";

  chdir "$ENV{HOME}/Code/s5/CONFIG_FILES";
  run "adb", "push",
    "%data%user%0%x1125io.initdlight%files%sdcard-userinit.sh",
    "/data/user/0/x1125io.initdlight/files/sdcard-userinit.sh",
    ;
  chdir "..";

  run "adb", "shell", "rm -rf /sdcard/userinit/";
  run "adb", "shell", "mkdir /sdcard/userinit/";
  for my $file(glob "$ENV{HOME}/Code/s5/userinit/*"){
    run "adb", "push", $file, "/sdcard/userinit/";
  }

  print "\n\nopen it up and start it, enable root perm\n";
}

sub run(@){
  print "@_\n";
  system @_;
}

&main(@ARGV);
