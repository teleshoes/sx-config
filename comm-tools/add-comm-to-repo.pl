#!/usr/bin/perl
use strict;
use warnings;

my $BACKUP_DIR = "$ENV{HOME}/Code/s5/backup";
my $SMS_REPO_DIR = "$BACKUP_DIR/backup-sms/repo";
my $CALL_REPO_DIR = "$BACKUP_DIR/backup-call/repo";

sub getSortKey($$);
sub readRepoFile($$);
sub writeRepoFile($$@);

sub parseFile($$);
sub parseSmsFile($);
sub parseCallFile($);

my $usage = "Usage:
  $0 --sms FILE
    parse FILE and add to $SMS_REPO_DIR

  $0 --call FILE
    parse FILE and add to $CALL_REPO_DIR
";

sub main(@){
  die $usage if @_ != 2 or $_[0] !~ /(sms|call)/;
  my ($type, $file) = @_;
  my $entries = parseFile $type, $file;
  for my $fileName(sort keys %$entries){
    my @newEntries = @{$$entries{$fileName}};
    my @repoEntries = readRepoFile $type, $fileName;

    my %allEntriesBySortKey;

    my %repoEntriesByLine;
    my $latestRepoEntry = undef;
    for my $entry(@repoEntries){
      if(not defined $latestRepoEntry or $$latestRepoEntry{date} < $$entry{date}){
        $latestRepoEntry = $entry;
      }
      my $line = $$entry{line};
      die "duplicate entry in repo: $line" if defined $repoEntriesByLine{$line};
      $repoEntriesByLine{$line} = $entry;

      my $sortKey = getSortKey $type, $entry;
      if(defined $allEntriesBySortKey{$sortKey}){
        my $prevEntry = $allEntriesBySortKey{$sortKey};
        die "duplicate entry:\n  $$prevEntry{line}  $$entry{line}";
      }
      $allEntriesBySortKey{$sortKey} = $entry;
    }

    for my $entry(@newEntries){
      my $line = $$entry{line};
      if(defined $repoEntriesByLine{$line}){
        #ignore exact duplicates from repo
        next;
      }
      if(defined $latestRepoEntry and $$entry{date} <= $$latestRepoEntry{date}){
        my ($newLine, $oldLine) = ($$entry{line}, $$latestRepoEntry{line});
        die "new entry older than last repo entry:\nnew: ${newLine}old: ${oldLine}";
      }

      my $sortKey = getSortKey $type, $entry;
      if(defined $allEntriesBySortKey{$sortKey}){
        my $prevEntry = $allEntriesBySortKey{$sortKey};
        die "duplicate entry:\n  $$prevEntry{line}  $$entry{line}";
      }
      $allEntriesBySortKey{$sortKey} = $entry;
    }

    my @sortedEntries = map {$allEntriesBySortKey{$_}} sort keys %allEntriesBySortKey;
    writeRepoFile($type, $fileName, @sortedEntries);
  }
}

sub getSortKey($$){
  my ($type, $entry) = @_;

  if($type =~ /sms/){
    return join "|", (
      $$entry{num},
      $$entry{date},
      $$entry{dateSent},
      $$entry{source},
      $$entry{dir},
      $$entry{body},
    );
  }elsif($type =~ /call/){
    return join "|", (
      $$entry{num},
      $$entry{date},
      $$entry{dir},
      $$entry{duration},
    );
  }else{
    die "invalid type: $type\n";
  }
}

sub readRepoFile($$){
  my ($type, $fileName) = @_;
  my $repoFile;
  if($type =~ /sms/){
    $repoFile = "$SMS_REPO_DIR/$fileName.sms";
  }elsif($type =~ /call/){
    $repoFile = "$CALL_REPO_DIR/$fileName.call";
  }else{
    die "invalid type: $type\n";
  }
  if(not -f $repoFile){
    return ();
  }
  my $repoEntries = parseFile $type, $repoFile;
  my @numsInRepoFile = sort keys %$repoEntries;
  if(@numsInRepoFile == 0){
    return ();
  }
  if($fileName ne "+++"){
    #except for the misc +++ file,
    #  all files should have exactly one number,
    #  and it should exactly match the file name
    if(@numsInRepoFile != 1 or $numsInRepoFile[0] ne $fileName){
      die "different number in repo file: @numsInRepoFile\n";
    }
  }
  my @entries;
  for my $num(@numsInRepoFile){
    @entries = (@entries, @{$$repoEntries{$num}});
  }
  return @entries;
}
sub writeRepoFile($$@){
  my ($type, $fileName, @entries) = @_;
  my $repoFile;
  if($type =~ /sms/){
    $repoFile = "$SMS_REPO_DIR/$fileName.sms";
  }elsif($type =~ /call/){
    $repoFile = "$CALL_REPO_DIR/$fileName.call";
  }else{
    die "invalid type: $type\n";
  }
  open FH, "> $repoFile" or die "could not write $repoFile\n$!\n";
  print FH $$_{line} foreach @entries;
  close FH;
}

sub parseFile($$){
  my ($type, $file) = @_;
  if($type =~ /sms/){
    return parseSmsFile $file;
  }elsif($type =~ /call/){
    return parseCallFile $file;
  }else{
    die "invalid type: $type\n";
  }
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
