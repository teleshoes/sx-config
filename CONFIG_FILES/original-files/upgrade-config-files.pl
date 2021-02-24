#!/usr/bin/perl
use strict;
use warnings;

sub md5sum($);

sub main(@){
  my @releases = reverse sort glob "*.*.*.*";
  my $targetRelease = $releases[0];

  my @boingFiles = glob "$targetRelease/%*";
  s/^$targetRelease\/// foreach @boingFiles;

  for my $boingFile(@boingFiles){
    $boingFile =~ s/^\.\.\///;
    my $mostRecentVer = undef;
    for my $rel(@releases){
      next if $rel eq $targetRelease;
      if(-e "$rel/$boingFile"){
        $mostRecentVer = $rel;
        last;
      }
    }

    my $oldOrigFile;
    if(defined $mostRecentVer){
      $oldOrigFile = "$mostRecentVer/$boingFile";
    }else{
      $mostRecentVer = "EMPTY";
      $oldOrigFile = "empty-$boingFile";
      system "touch $oldOrigFile";
    }

    my $newOrigFile = "$targetRelease/$boingFile";
    my $curFile = "../$boingFile";
    my $oldMd5 = md5sum $oldOrigFile;
    my $newMd5 = md5sum $newOrigFile;
    if($oldMd5 eq $newMd5){
      printf "%-10s %s\n", "unchanged", $boingFile;
      next;
    }

    my $canWrite = -w $curFile;
    if(not $canWrite){
      system "chmod", "u+w", $curFile;
    }

    system "git", "merge-file",
      "-L", "edit-$mostRecentVer", "-L", "$mostRecentVer", "-L", "$targetRelease",
      $curFile, $oldOrigFile, $newOrigFile;
    my $success = $? == 0;
    if($success){
      printf "%-10s %s\n", "merged", $boingFile;
    }else{
      printf "%-10s %s\n", "CONFLICTS", $boingFile;
    }

    if(not $canWrite){
      system "chmod", "u-w", $curFile;
    }
    if(-e "empty-$boingFile"){
      system "rm", "empty-$boingFile";
    }
  }
}

sub md5sum($){
  my $md5 = `md5sum $_[0]`;
  if($md5 =~ /^([0-9a-f]{32})\s/){
    return $1;
  }else{
    die "ERROR: could not parse md5sum for $_[0]\n";
  }
}

&main(@ARGV);
