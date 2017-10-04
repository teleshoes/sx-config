#!/usr/bin/perl
use strict;
use warnings;

my $DIR = "$ENV{HOME}/Code/s5";

sub run(@);

sub main(@){
  chdir "$DIR/apks";
  run "adb", "uninstall", "ru.meefik.linuxdeploy";
  run "adb", "install", "linuxdeploy-2.0-beta2.apk";

  my $linuxDeployProperties = "%data%data%ru.meefik.linuxdeploy%shared_prefs%properties_conf.xml";
  my $linuxDeploySettings = "%data%data%ru.meefik.linuxdeploy%shared_prefs%settings_conf.xml";

  my $props = `cat $DIR/CONFIG_FILES/$linuxDeployProperties`;

  my $debUUID = `adb shell blkid -l -s UUID -o value -t LABEL=SD_DEB`;
  $debUUID =~ s/\r|\n//g;

  my $targetPath = "/mnt/media_rw/$debUUID";
  my $targetPathElem = "<string name=\"target_path\">$targetPath<\/string>";
  $props =~ s/<string name="target_path">.*<\/string>/$targetPathElem/;
  open FH, "> $DIR/CONFIG_FILES/$linuxDeployProperties";
  print FH $props;
  close FH;

  chdir "$DIR/CONFIG_FILES";
  run "./upload-app-conf.pl", $linuxDeployProperties;
  run "./upload-app-conf.pl", $linuxDeploySettings;

  print "open it up and start it, enable root perm\n";
  print "then wait a sec, stop it, and start it. should be good to go\n";
  print "if it doesnt auto-start on reboot, disable autostart, close linuxdeploy, open linuxdeploy, enable autostart, reboot\n";
}



sub run(@){
  print "@_\n";
  system @_;
}

&main(@ARGV);
