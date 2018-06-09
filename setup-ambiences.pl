#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(time);
use List::Util qw(max);
use File::Basename qw(basename);

my $wallpaperDir = "/home/nemo/Backgrounds/sx-ambience";
my $ambienceDir = "/usr/share/ambience";

my @ambienceOrder = qw(seconds ada neko silent);
my $ambiences = {
  ada     => [1, "$wallpaperDir/artwork/ada_crop9x16.jpg", {}],
  neko    => [1, "$wallpaperDir/neko/neko_kutie_ontable.jpg", {}],
  seconds => [1, "$wallpaperDir/artwork/seconds.jpg", {}],

  silent  => [1, "$wallpaperDir/sarah/sarah_crop9x16.jpg", {
    "ringerVolume"            => "0",

    "highlightColor"          => "\"#ff66a8ff\"",
    "secondaryHighlightColor" => "\"#ff8569db\"",
    "primaryColor"            => "\"#FFFFFFFF\"",
    "secondaryColor"          => "\"#B0FFFFFF\"",
  }],
};

my $preloadAmbience = "$ambienceDir/$ambienceOrder[0]/$ambienceOrder[0].ambience";
my $preloadDir = "/usr/share/jolla-preload/ambience";
my @preloadConfFiles = qw(
  ambience-Jolla_C.conf
  ambience-Xperia_X.conf
  ambience-default.conf
  ambience-origami.conf
);

sub getDefaultAmbienceConfig($);
sub getValidConfigKeys();
sub run(@);

sub main(@){
  my $nowMillis = int(time * 1000);

  my $tmpAmbienceDir = "/tmp/sx-ambiences-$nowMillis";

  for my $ambienceName(@ambienceOrder){
    run "mkdir", "-p", "$tmpAmbienceDir/$ambienceName";
    my ($isFavorite, $wallpaperPath, $extraConfig) = @{$$ambiences{$ambienceName}};
    my $wallpaperFileName = basename $wallpaperPath;

    my $defaultConfig = getDefaultAmbienceConfig($ambienceName);

    my %config = (%$defaultConfig, %$extraConfig);
    $config{wallpaper} = "\"$wallpaperFileName\"";
    $config{favorite} = $isFavorite ? "true" : "false";

    my @validConfigKeys = @{getValidConfigKeys()};
    my $maxKeyLen = max map {length $_} @validConfigKeys;

    my @configLines;
    for my $configKey(@validConfigKeys){
      next if not defined $config{$configKey};
      my $spacer = " " x ($maxKeyLen - length $configKey);
      my $fmt = "    \"$configKey\"$spacer   : $config{$configKey}";
      push @configLines, $fmt;
    }
    my $configFormat = "{\n" . (join ",\n", @configLines) . "\n}\n";
    open FH, "> $tmpAmbienceDir/$ambienceName/$ambienceName.ambience";
    print FH $configFormat;
    close FH;

    run "mkdir", "-p", "$tmpAmbienceDir/$ambienceName/images";
    run "ln", "-s",
      "$wallpaperPath",
      "$tmpAmbienceDir/$ambienceName/images/$wallpaperFileName"
      ;
  }

  my $host = `sx`;
  chomp $host;

  run "sx", "-u", "root", "mv $ambienceDir $ambienceDir-bak$nowMillis";
  run "rsync", "-avP", "--no-owner", "--no-group", "$tmpAmbienceDir/", "root\@$host:$ambienceDir/";
  my @cmds = (
    "rm -rf /home/nemo/.local/share/system/privileged/Ambienced/",
    "rm -rf /home/nemo/.local/share/ambienced/",
    "rm -rf /home/nemo/.cache/ambienced/",
  );
  for my $file(@preloadConfFiles){
    push @cmds, "echo $preloadAmbience > $preloadDir/$file";
  }
  run "sx", "-u", "root", join ";\n", @cmds;
  print "\n";

  print "try each of these, as nemo, in order, to attempt to see changes:\n";
  print "  systemctl --user restart ambienced\n";
  print "  systemctl --user restart lipstick\n";
  print "  sudo reboot\n";
}

sub getDefaultAmbienceConfig($){
  my ($ambienceName) = @_;

  my $timestamp = `date +%Y-%m-%dT%H:%M:%S`;
  chomp $timestamp;

  return {
    "translationCatalog"       => "\"ambience-$ambienceName\"",
    "displayName"              => "\"ambience-$ambienceName\"",
    "wallpaper"                => "\"\"",
    "highlightColor"           => "\"#ff81ffff\"",
    "secondaryHighlightColor"  => "\"#ff6cb7d4\"",
    "primaryColor"             => "\"#FFFFFFFF\"",
    "secondaryColor"           => "\"#B0FFFFFF\"",
    "ringerVolume"             => "80",
    "favorite"                 => "",
    "timestamp"                => "\"$timestamp\"",
    "version"                  => "2",

    # 0 means set tonefiles to 'no sound'
    # 1 means reset tonefiles to defaults
    # missing means leave tonefiles alone
#   "ringerToneFile"           => "{ \"enabled\": 1 }",
#   "messageToneFile"          => "{ \"enabled\": 1 }",
#   "mailToneFile"             => "{ \"enabled\": 1 }",
#   "internetCallToneFile"     => "{ \"enabled\": 1 }",
#   "chatToneFile"             => "{ \"enabled\": 1 }",
#   "calendarToneFile"         => "{ \"enabled\": 1 }",
#   "clockAlarmToneFile"       => "{ \"enabled\": 1 }",
  };
}
sub getValidConfigKeys(){
  return [qw(
    translationCatalog
    displayName
    wallpaper
    highlightColor
    secondaryHighlightColor
    primaryColor
    secondaryColor
    ringerVolume
    favorite
    timestamp
    version
    ringerToneFile
    messageToneFile
    mailToneFile
    internetCallToneFile
    chatToneFile
    calendarToneFile
    clockAlarmToneFile
  )];
}

sub run(@){
  print "@_\n";
  system @_;
  die "\"@_\" failed\n" if $? != 0;
}

&main(@ARGV);
