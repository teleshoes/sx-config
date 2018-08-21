#!/usr/bin/perl
use strict;
use warnings;

my $BACKUP_DIR = "$ENV{HOME}/Code/sx/backup";
my $SMS_REPO_DIR = "$BACKUP_DIR/backup-sms/repo";
my $CALL_REPO_DIR = "$BACKUP_DIR/backup-call/repo";

sub getSortKey($$);
sub readRepoFile($$);
sub writeRepoFile($$@);

sub stripMillisLine($$);
sub parseFile($$);
sub parseSmsFile($);
sub parseCallFile($);

sub hashEq($$);
sub arrEq($$);

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
    my %noMillisAllEntriesBySortKey;

    my %repoEntriesByLine;
    my %repoEntriesByLineNoMillis;
    my $latestRepoEntry = undef;
    for my $entry(@repoEntries){
      if(not defined $latestRepoEntry or $$latestRepoEntry{date} < $$entry{date}){
        $latestRepoEntry = $entry;
      }
      my $line = $$entry{line};
      die "duplicate entry in repo: $line" if defined $repoEntriesByLine{$line};
      $repoEntriesByLine{$line} = $entry;

      my $noMillisLine = stripMillisLine $type, $line;
      $repoEntriesByLineNoMillis{$noMillisLine} = $entry;

      my $sortKey = getSortKey $type, $entry;
      if(defined $allEntriesBySortKey{$sortKey}){
        my $prevEntry = $allEntriesBySortKey{$sortKey};
        if(hashEq $entry, $prevEntry){
          print STDERR "WARNING: duplicate entry:\n  $$prevEntry{line}";
        }else{
          die "ERROR: duplicate entry:\n  $$prevEntry{line}  $$entry{line}";
        }
      }else{
        $allEntriesBySortKey{$sortKey} = $entry;
      }
    }

    for my $entry(@newEntries){
      my $line = $$entry{line};
      if(defined $repoEntriesByLine{$line}){
        #ignore exact duplicates from repo
        next;
      }
      if(defined $repoEntriesByLineNoMillis{$line}){
        #ignore entries that are identical except for milliseconds from repo
        next;
      }
      if(defined $latestRepoEntry and $$entry{date} <= $$latestRepoEntry{date}){
        my ($newLine, $oldLine) = ($$entry{line}, $$latestRepoEntry{line});
        die "new entry older than last repo entry:\nnew: ${newLine}old: ${oldLine}";
      }

      my $sortKey = getSortKey $type, $entry;
      if(defined $allEntriesBySortKey{$sortKey}){
        my $prevEntry = $allEntriesBySortKey{$sortKey};
        if(hashEq $prevEntry, $entry){
          print STDERR "WARNING: duplicate entry:\n  $$prevEntry{line}";
        }else{
          die "ERROR: duplicate entry:\n  $$prevEntry{line}  $$entry{line}";
        }
      }else{
        $allEntriesBySortKey{$sortKey} = $entry;
      }
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
  my $maxDateMillis = undef;
  for my $entry(@entries){
    if(not defined $maxDateMillis or $$entry{date} > $maxDateMillis){
      $maxDateMillis = $$entry{date};
    }
  }
  open FH, "> $repoFile" or die "could not write $repoFile\n$!\n";
  print FH $$_{line} foreach @entries;
  close FH;

  if(defined $maxDateMillis){
    my $mtime = int($maxDateMillis / 1000.0 + 0.5);
    system "touch", $repoFile, "--date", "\@$mtime";
  }
}

sub stripMillisLine($$){
  my ($type, $line) = @_;
  if($type =~ /sms/){
    if($line !~ s/^([0-9+*#]*),(\d+)\d\d\d,(\d+)\d\d\d,/${1},${2}000,${3}000,/){
      die "could not remove millis from line: $line";
    }
  }
  if($type =~ /call/){
    if($line !~ s/^([0-9+*#]*),(\d+)\d\d\d,/${1},${2}000,/){
      die "could not remove millis from line: $line";
    }
  }
  return $line;
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

sub hashEq($$){
  my ($hashOne, $hashTwo) = @_;
  return 1 if not defined $hashOne and not defined $hashTwo;
  return 0 if not defined $hashOne or not defined $hashTwo;

  my @keysOne = sort keys %$hashOne;
  my @keysTwo = sort keys %$hashTwo;

  return 0 if not arrEq \@keysOne, \@keysTwo;

  for my $key(@keysOne){
    return 0 if not $$hashOne{$key} eq $$hashTwo{$key};
  }
  return 1;
}

sub arrEq($$){
  my ($arrOne, $arrTwo) = @_;
  return 1 if not defined $arrOne and not defined $arrTwo;
  return 0 if not defined $arrOne or not defined $arrTwo;

  return 0 if not @$arrOne == @$arrTwo;

  for(my $i=0; $i<@$arrOne; $i++){
    if($$arrOne[$i] ne $$arrTwo[$i]){
      return 0;
    }
  }
  return 1;
}

&main(@ARGV);
