#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(time);
use File::Basename qw(basename);

my $hostName = "wolke-sx";

my $DIR = '/opt/CONFIG_FILES';
my $BAK_DIR_PREFIX = '/opt/CONFIG_FILES_BACKUP';
my $user = "nemo";
my ($login,$pass,$uid,$gid) = getpwnam($user);
my $binTarget = '/usr/local/bin';

my @rsyncOpts = qw(
  -a  --no-owner --no-group
  --out-format=%n
);

my %symlinksToReplace = map {$_ => 1} (
);

my %changedTriggers = (
);

my $okTypes = join "|", qw(boing bin remove all);

my $usage = "Usage:
  $0 [OPTS] $okTypes
    overwrite boing, bin, remove, or all files
    NOTE: does NOT backup any files
          see --backup-only option, which ONLY runs backup

  $0 [OPTS]
    same as $0 all

  OPTS
    --backup-only
      instead of overwriting files, copy all files to ${BAK_DIR_PREFIX}_<NOW_MILLIS>
";

sub backupFile($$);
sub overwriteFile($$$);
sub removeFile($);
sub md5sum($);
sub nowMillis();

sub main(@){
  my $backupOnlyMode = 0;
  if(@_ >= 1 and $_[0] =~ /^(--backup-only)$/){
    shift;
    $backupOnlyMode = 1;
  }

  my $type = 'all';
  $type = shift if @_ > 0 and $_[0] =~ /^($okTypes)$/;

  die $usage if @_ > 0;

  die "hostname must be $hostName" if `hostname` ne "$hostName\n";

  my $backupDir = "${BAK_DIR_PREFIX}_" . nowMillis();
  if($backupOnlyMode){
    system "mkdir", "-p", $backupDir;
  }

  my @boingFiles = glob "$DIR/%*";
  s/^$DIR\/// foreach @boingFiles;

  my @filesToRemove = `cat $DIR/config-files-to-remove`;
  chomp foreach @filesToRemove;

  my %triggers;

  if($type =~ /^(boing|all)$/){
    print "\n ---handling boing files...\n";
    for my $file(@boingFiles){
      my $dest = $file;
      $dest =~ s/%/\//g;
      my ($old, $new);
      if(defined $changedTriggers{$dest}){
        $old = md5sum $dest;
      }
      if($backupOnlyMode){
        backupFile $backupDir, $dest;
      }else{
        overwriteFile "$DIR/$file", $dest, 1;
      }
      if(defined $changedTriggers{$dest}){
        $new = md5sum $dest;
        if($old ne $new){
          print "   ADDED TRIGGER: $changedTriggers{$dest}\n";
          $triggers{$changedTriggers{$dest}} = 1;
        }
      }
    }
  }

  if($type =~ /^(bin|all)$/){
    print "\n ---handling bin files...\n";
    if($backupOnlyMode){
      for my $file(glob "$DIR/bin/*"){
        my $baseName = basename $file;
        my $binFile = "$binTarget/$baseName";
        backupFile $backupDir, $binFile;
      }
    }else{
      overwriteFile "$DIR/bin/", "$binTarget/", 0;
    }
  }

  if($type =~ /^(remove|all)$/){
    print "\n ---removing files to remove...\n";
    for my $file(@filesToRemove){
      chomp $file;
      if($backupOnlyMode){
        backupFile $backupDir, $file;
      }else{
        removeFile $file;
      }
    }
  }

  print "\n ---running triggers...\n";
  for my $trigger(keys %triggers){
    print "  $trigger: \n";
    if($backupOnlyMode){
      print "WARNING: backup only mode, NOT running trigger: $trigger\n";
    }else{
      system $trigger;
    }
  }
  if($backupOnlyMode){
    print "backup only mode, NOT touching /etc/sudoers\n";
  }else{
    system "chmod", "0440", "/etc/sudoers";
  }
}

sub backupFile($$){
  my ($backupDir, $file) = @_;
  my $dest = $file;
  $dest =~ s/\//%/g;
  if(-e $file){
    print "backing up $file\n";
    system "cp", "-ar", $file, "$backupDir/$dest";
  }
}

sub overwriteFile($$$){
  my ($src, $dest, $del) = @_;

  my $parentDir = $dest;
  $parentDir =~ s/\/[^\/]*$//;
  if(not -d $parentDir){
    if($parentDir =~ /^\/home\/$user/){
      system "sudo", "-u", "nemo", "mkdir", "-p", $parentDir;
    }else{
      system "mkdir", "-p", $parentDir;
    }
  }

  print "\n   %%% $dest\n";
  my @rsyncCmd = ("rsync", @rsyncOpts);
  push @rsyncCmd, "--del" if $del;
  if(-l $src){
    system "rm", $dest if -l $dest;

    my $srcLink = readlink $src;
    if(defined $symlinksToReplace{$dest}){
      system "cp", $srcLink, $dest;
    }elsif(not -e $dest){
      system "ln", "-s", $srcLink, $dest;
    }else{
      die "Cannot replace non-symlink with symlink\n";
    }
  }elsif(-d $src){
    system @rsyncCmd, "$src/", "$dest";
  }else{
    system @rsyncCmd, "$src", "$dest";
  }

  my @chownFiles = ($dest);
  if(not -l $dest and -d $dest){
    @chownFiles = (@chownFiles, glob("$dest/*"));
  }

  my ($chownUid, $chownGid);
  if($dest =~ /^\/home\/$user/){
    ($chownUid, $chownGid) = ($uid, $gid);
  }elsif($dest =~ /^(\/opt\/alien\/data\/data\/[^\/]+)\//){
    my $alienAppDir = $1;
    my @alienAppDirStat = stat $alienAppDir;
    my ($alienUID, $alienGID) = ($alienAppDirStat[4], $alienAppDirStat[5]);
    ($chownUid, $chownGid) = ($alienUID, $alienGID);
  }else{
    ($chownUid, $chownGid) = (0, 0);
  }

  if(-l $dest){
    system "chown", "-h", "$chownUid.$chownGid", @chownFiles;
  }else{
    chown $chownUid, $chownGid, @chownFiles;
  }
}

sub removeFile($){
  my $file = shift;
  if(-e $file){
    if(-d $file){
      $file =~ s/\/$//;
      $file .= '/';
      print "\nremoving these files in $file:\n";
      system "find $file";
    }else{
      print "\nremoving $file\n";
    }
    system "rm -r $file";
  }
}

sub md5sum($){
  my $file = shift;
  my $out;
  if(-d $file){
    $out = `find "$file" -type f -exec md5sum {} \\; 2>/dev/null | sort`;
  }else{
    $out = `md5sum $file 2>/dev/null`;
    chomp $out;
  }
  return $out;
}

sub nowMillis(){
  return int(time * 1000.0 + 0.5);
}

&main(@ARGV);
