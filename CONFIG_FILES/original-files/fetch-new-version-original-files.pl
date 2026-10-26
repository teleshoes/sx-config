#!/usr/bin/perl
use strict;
use warnings;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $IPMAGIC_NAME = "sx";
my $DIR = abs_path(dirname($0));

my $USAGE = "Usage:
  $0 -f | --fetch
    -fetch version name from /etc/issue
    -fetch files from /opt/CONFIG_FILES_BACKUP_*
    -copy files locally to $DIR/<VERSION>
    -remove files in $DIR/<VERSION> that are identical to the previous version
";

sub md5sum($);

sub main(@){
  die $USAGE unless @_ == 1 and $_[0] =~ /^(-f|--fetch)$/;

  my $issue = `ipmagic $IPMAGIC_NAME cat /etc/issue`;
  if($issue !~ /^Sailfish OS ([0-9\.]+)(?: \(.*\))?$/m){
    die "ERROR: could not parse version from /etc/issue\n";
  }
  my $version = $1;

  my $backupDir = `ipmagic $IPMAGIC_NAME ls -d /opt/CONFIG_FILES_BACKUP_*`;
  chomp $backupDir;
  if($backupDir !~ /^\/opt\/CONFIG_FILES_BACKUP_\d+$/){
    die "ERROR: exactly one CONFIG_FILES backup must be present\n";
  }

  my $host = `ipmagic $IPMAGIC_NAME`;
  chomp $host;

  system "rm -rf $DIR/$version/";
  system "rsync -avP --no-owner root\@$host:$backupDir/ $DIR/$version/";

  print "\n\n";
  my @files = `find '$DIR/$version' -not -type d`;
  chomp foreach @files;

  for my $file(@files){
    if($file !~ /^$DIR\/$version\/(%.+)$/){
      die "ERROR: malformed file returned from glob\n$file\n";
    }
    my $fileName = $1;

    if(-l $file){
      print "deleting symlink $file\n";
      system "rm -f $file";
      next;
    }
    if(not -f $file){
      die "ERROR: $file is not a file\n";
    }

    my @altVersions =
      reverse
      sort
      grep {$_ !~ /^$DIR\/$version\//}
      glob "$DIR/*/$fileName";

    my $latestAlt = $altVersions[0] if @altVersions > 0;
    if(defined $latestAlt){
      my $newMd5 = md5sum $file;
      my $oldMd5 = md5sum $latestAlt;
      if($oldMd5 eq $newMd5){
        print "deleting $file\n dupe of $latestAlt\n";
        system "rm -f $file";
      }
    }

    my $curModCfgFile = "$DIR/../$fileName";
    if(not -f $curModCfgFile and $fileName =~ /^%usr%local%bin%(.*)$/){
      $curModCfgFile = "$DIR/../bin/$1";
    }

    if(-f $file && -f $curModCfgFile){
      my $newMd5 = md5sum $file;
      my $curModCfgMd5 = md5sum $curModCfgFile;
      if($curModCfgMd5 eq $newMd5){
        print "deleting $file\n dupe of already-edited $curModCfgFile\n";
        system "rm -f $file";
      }
    }
  }

  system "find '$DIR/$version' -depth -type d -empty -delete";
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
