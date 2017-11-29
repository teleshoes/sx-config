#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(time);

my $BACKUP_DIR = "$ENV{HOME}/Code/sx/backup";
my $SMS_REPO_DIR = "$BACKUP_DIR/backup-sms/repo";
my $CALL_REPO_DIR = "$BACKUP_DIR/backup-call/repo";

my $SOME_COUNT = 3;
my $RECENT_SOME_CUTOFF_DAYS = 365;
my $RECENT_SOME_CUTOFF_MILLIS = $RECENT_SOME_CUTOFF_DAYS * 24 * 60 * 60 * 1000;

my $RECENT_ALL_CUTOFF_DAYS = 90;
my $RECENT_ALL_CUTOFF_MILLIS = $RECENT_ALL_CUTOFF_DAYS * 24 * 60 * 60 * 1000;

sub getSortKey($$);

sub parseRepoFileFlat($$);
sub parseSmsFile($);
sub parseCallFile($);

my $usage = "Usage:
  $0 COMM_TYPE
    print recent comm entries (SMS or calls) from all contacts
      includes all in the last $RECENT_ALL_CUTOFF_DAYS days,
      plus $SOME_COUNT per contact in the last $RECENT_SOME_CUTOFF_DAYS days

  COMM_TYPE
    sms
      (any string that contains 'sms', e.g.: --sms, sms, spasms)
      process SMS messages
      excludes messages of type=M (MMS messages in SMS csv files)
    call
      (any string that contains 'call', e.g.: --calls, call, calliope)
      process calls
";

sub main(@){
  die $usage if @_ != 1 or $_[0] !~ /(sms|call)/;
  my ($type) = @_;
  my @files;
  @files = glob "$SMS_REPO_DIR/*.sms" if $type =~ /sms/;
  @files = glob "$CALL_REPO_DIR/*.call" if $type =~ /call/;
  my $nowMillis = int(time * 1000);
  for my $file(sort @files){
    my @entries = parseRepoFileFlat $type, $file;
    my @recent;
    for my $entry(reverse @entries){
      next if defined $$entry{source} and $$entry{source} eq "M";
      my $diffMillis = $nowMillis - $$entry{date};
      if($diffMillis < 0){
        die "future entry: $$entry{line}\n";
      }
      if($diffMillis < $RECENT_ALL_CUTOFF_MILLIS){
        push @recent, $entry;
      }elsif($diffMillis < $RECENT_SOME_CUTOFF_MILLIS and @recent < $SOME_COUNT){
        push @recent, $entry;
      }else{
        last; #all entries will be later
      }
    }
    for my $entry(reverse @recent){
      if(defined $$entry{num} and length $$entry{num} > 0){
        print $$entry{line};
      }
    }
  }
}

sub parseRepoFileFlat($$){
  my ($type, $file) = @_;
  my $entries;
  if($type =~ /sms/){
    $entries = parseSmsFile $file;
  }elsif($type =~ /call/){
    $entries = parseCallFile $file;
  }else{
    die "invalid type: $type\n";
  }
  my @nums = keys %$entries;
  if(@nums == 0){
    die "empty repo file: $file\n";
  }elsif(@nums > 1){
    die "multiple contact numbers in a single repo file: $file\n";
  }
  my $repoEntries = $$entries{$nums[0]};
  return @$repoEntries;
}
sub parseSmsFile($){
  my ($file) = @_;
  open FH, "< $file" or die "could not read $file\n$!\n";
  my $entries = {};
  while(my $line = <FH>){
    my $dateFmtRe = '\\d\\d\\d\\d-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d';
    if($line !~ /^([0-9+*#]*),(\d+),(\d+),(S|M),(OUT|INC),($dateFmtRe),"(.*)"$/){
      die "invalid sms line: $line";
    }
    my ($num, $date, $dateSent, $source, $dir, $dateFmt, $body) =
      ($1, $2, $3, $4, $5, $6, $7);

    #empty numbers and weird numbers go in "+++.sms"
    my $fileName = $num;
    if($fileName eq "" or $fileName =~ /[^0-9+]/){
      $fileName = "+++";
    }

    if(not defined $$entries{$fileName}){
      $$entries{$fileName} = [];
    }
    push @{$$entries{$fileName}}, {
      line => $line,
      num => $num,
      date => $date,
      dateSent => $dateSent,
      source => $source,
      dir => $dir,
      dateFmt => $dateFmt,
      body => $body,
    };
  }
  return $entries;
}
sub parseCallFile($){
  my ($file) = @_;
  open FH, "< $file" or die "could not read $file\n$!\n";
  my $entries = {};
  while(my $line = <FH>){
    my $dateFmtRe = '\\d\\d\\d\\d-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d';
    if($line !~ /^([0-9+*#]*),(\d+),(OUT|INC|MIS|REJ|BLK),($dateFmtRe),\s*(-?)(\d+)h\s*(\d+)m\s(\d+)s$/){
      die "invalid call line: $line";
    }
    my ($num, $date, $dir, $dateFmt, $durSign, $durH, $durM, $durS) =
      ($1, $2, $3, $4, $5, $6, $7, $8);
    my $duration = ($durH*60*60 + $durM*60 + $durS) * ($durSign =~ /-/ ? -1 : 1);

    #empty numbers and weird numbers go in "+++.call"
    my $fileName = $num;
    if($fileName eq "" or $fileName =~ /[^0-9+]/){
      $fileName = "+++";
    }

    if(not defined $$entries{$fileName}){
      $$entries{$fileName} = [];
    }
    push @{$$entries{$fileName}}, {
      line => $line,
      num => $num,
      date => $date,
      dir => $dir,
      dateFmt => $dateFmt,
      duration => $duration,
    };
  }
  return $entries;
}

&main(@ARGV);
