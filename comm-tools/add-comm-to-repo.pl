#!/usr/bin/perl
use strict;
use warnings;
use utf8;

my $BACKUP_DIR = "$ENV{HOME}/Code/sx/backup";
my $SMS_REPO_DIR = "$BACKUP_DIR/backup-sms/repo";
my $CALL_REPO_DIR = "$BACKUP_DIR/backup-call/repo";

my $DEFAULT_FUZZY_DUPE_MILLIS = 5 * 60 * 1000; #5 minutes

my $DUPE_MODE_EXACT = "exact";
my $DUPE_MODE_MILLIS = "millis";
my $DUPE_MODE_FUZZY = "fuzzy";
my $DUPE_MODE_REGEX = join "|", ($DUPE_MODE_EXACT, $DUPE_MODE_MILLIS, $DUPE_MODE_FUZZY);

sub readRepoFile($$);
sub writeRepoFile($$@);

sub parseFile($$);
sub parseSmsFile($);
sub parseCallFile($);
sub getEntryHash($$$);
sub isDateDupe($$$$);

my $usage = "Usage:
  $0 -h|--help
    show this message

  $0 [OPTS] --sms FILE
    parse FILE and add to $SMS_REPO_DIR
    ignores duplicate entries, and entries that are the same except for milliseconds

  $0 [OPTS] --call FILE
    parse FILE and add to $CALL_REPO_DIR
    ignores duplicate entries, and entries that are the same except for milliseconds

  OPTS
    --allow-old
      do not fail if a new entry is older than the newest entry in the repo

    --dupe=DUPE_MODE
      set criteria for which entries are considered duplicates for ignoring

      DUPE_MODE
        $DUPE_MODE_EXACT
          only ignore entries that are exactly identical to an entry in the repo
            (date must match, including milliseconds)
            (dateSent must match, if present, including milliseconds)

        $DUPE_MODE_MILLIS
          (this is the default)
          ignore entries that are identical to an entry in the repo, except for date/dateSent/dateFmt,
            AND date matches if you truncate milliseconds (floor, not round-half-up)
            AND dateSent (if present) matches if you truncate milliseconds (floor, not round-half-up)

        $DUPE_MODE_FUZZY
          ignore entries that are identical to an entry in the repo, except for date/dateSent/dateFmt,
            AND date is within ${DEFAULT_FUZZY_DUPE_MILLIS} milliseconds
            AND dateSent (if present) is within ${DEFAULT_FUZZY_DUPE_MILLIS} milliseconds

    --fuzzy-whitespace-dupes
      remove leading and trailing whitespace from SMS body when considering duplicates

    --fuzzy-dupe-millis=FUZZY_DUPE_MILLIS
      for DUPE_MODE=$DUPE_MODE_FUZZY, use FUZZY_DUPE_MILLIS instead of $DEFAULT_FUZZY_DUPE_MILLIS millis
";

sub main(@){
  my $type;
  my $file;
  my $allowOld = 0;
  my $dupeMode = $DUPE_MODE_MILLIS;
  my $fuzzyDupeMillis = $DEFAULT_FUZZY_DUPE_MILLIS;
  my $isFuzzyWhitespaceDupes = 0;
  while(@_ > 0){
    my $arg = shift @_;
    if($arg =~ /^(-h|--help)$/){
      print $usage;
      exit 0;
    }elsif($arg =~ /^(-|--)?(sms|call)$/){
      die "ERROR: sms/call type specified more than once\n" if defined $type;
      $type = $2;
    }elsif($arg =~ /^(--allow-old)$/){
      $allowOld = 1;
    }elsif($arg =~ /^--dupe=($DUPE_MODE_REGEX)$/){
      $dupeMode = $1;
    }elsif($arg =~ /^(--fuzzy-whitespace-dupes)$/){
      $isFuzzyWhitespaceDupes = 1;
    }elsif($arg =~ /^--fuzzy-dupe-millis=(\d+)$/){
      $fuzzyDupeMillis = $1;
    }elsif(-f $arg){
      die "ERROR: can only specify one FILE\n" if defined $file;
      $file = $arg;
    }else{
      die "$usage\nERROR: unknown arg $arg\n";
    }
  }
  die "$usage\nERROR: missing --sms/--call\n" if not defined $type;
  die "$usage\nERROR: missing SMS/call file\n" if not defined $file;

  my $entriesByFileName = parseFile $type, $file;
  for my $repoFileName(sort keys %$entriesByFileName){
    my @newEntries = @{$$entriesByFileName{$repoFileName}};
    my @repoEntries = readRepoFile $type, $repoFileName;

    my $latestRepoEntry = undef;
    my %seenRepoLines;
    for my $entry(@repoEntries){
      if(not defined $latestRepoEntry or $$latestRepoEntry{date} < $$entry{date}){
        $latestRepoEntry = $entry;
      }
      if(defined $seenRepoLines{$$entry{line}}){
        die "ERROR: duplicate entry in repo: $$entry{line}";
      }
      $seenRepoLines{$$entry{line}} = 1;
    }

    my %repoDateValsByHash;
    my %repoDateSentValsByHash;
    for my $repoEntry(@repoEntries){
      my $line = $$repoEntry{line};
      my $hash = getEntryHash($type, $isFuzzyWhitespaceDupes, $repoEntry);
      $repoDateValsByHash{$hash} = [] if not defined $repoDateValsByHash{$hash};
      push @{$repoDateValsByHash{$hash}}, $$repoEntry{date};
      if(defined $$repoEntry{dateSent}){
        $repoDateSentValsByHash{$hash} = [] if not defined $repoDateSentValsByHash{$hash};
        push @{$repoDateSentValsByHash{$hash}}, $$repoEntry{dateSent};
      }
    }

    my @entriesToAdd;
    for my $entry(@newEntries){
      my $hash = getEntryHash($type, $isFuzzyWhitespaceDupes, $entry);

      my $dateDupeFound = 0;
      my @repoDateVals = @{$repoDateValsByHash{$hash}} if defined $repoDateValsByHash{$hash};
      for my $repoDate(@repoDateVals){
        if(isDateDupe($dupeMode, $fuzzyDupeMillis, $$entry{date}, $repoDate)){
          $dateDupeFound = 1;
        }
      }

      my $dupeEntry = 0;
      if(defined $$entry{dateSent}){
        my @repoDateSentVals = @{$repoDateSentValsByHash{$hash}} if defined $repoDateSentValsByHash{$hash};
        my $dateSentDupeFound = 0;
        for my $repoDateSent(@repoDateSentVals){
          if(isDateDupe($dupeMode, $fuzzyDupeMillis, $$entry{dateSent}, $repoDateSent)){
            $dateSentDupeFound = 1;
          }
        }
        $dupeEntry = $dateDupeFound and $dateSentDupeFound ? 1 : 0;
      }else{
        $dupeEntry = $dateDupeFound ? 1 : 0;
      }

      if($dupeEntry){
        next;
      }
      if(not $allowOld){
        if(defined $latestRepoEntry and $$entry{date} <= $$latestRepoEntry{date}){
          my ($newLine, $oldLine) = ($$entry{line}, $$latestRepoEntry{line});
          die "ERROR: new entry older than last repo entry:\nnew: ${newLine}old: ${oldLine}";
        }
      }
      push @entriesToAdd, $entry;
    }

    my @allEntries = (@repoEntries, @entriesToAdd);
    @allEntries = sort {$$a{line} cmp $$b{line}} @allEntries;

    writeRepoFile($type, $repoFileName, @allEntries);
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

  open FH, ">:encoding(UTF-8)", $repoFile or die "could not write $repoFile\n$!\n";
  for my $entry(@entries){
    print FH $$entry{line};
  }
  close FH;

  if(defined $maxDateMillis){
    my $mtime = int($maxDateMillis / 1000.0 + 0.5);
    system "touch", $repoFile, "--date", "\@$mtime";
  }
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
    utf8::decode($line);
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
    utf8::decode($line);
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

sub getEntryHash($$$){
  my ($type, $isFuzzyWhitespaceDupes, $entry) = @_;

  if($type =~ /sms/){
    my $body = $$entry{body};
    $body =~ s/^(\s|\\n)+// if $isFuzzyWhitespaceDupes;
    $body =~ s/(\s|\\n)+$// if $isFuzzyWhitespaceDupes;
    return join "|", (
      $$entry{num},
      $$entry{source},
      $$entry{dir},
      $body,
    );
    #ignored:
    #  $$entry{line},
    #  $$entry{date},
    #  $$entry{dateSent},
    #  $$entry{dateFmt},
  }elsif($type =~ /call/){
    return join "|", (
      $$entry{num},
      $$entry{dir},
      $$entry{duration},
    );
    #ignored:
    #  $$entry{line},
    #  $$entry{date},
    #  $$entry{dateFmt},
  }else{
    die "invalid type: $type\n";
  }
}

sub isDateDupe($$$$){
  my ($dupeMode, $fuzzyDupeMillis, $date1, $date2) = @_;
  if($dupeMode eq $DUPE_MODE_EXACT){
    return $date1 == $date2;
  }elsif($dupeMode eq $DUPE_MODE_MILLIS){
    return int($date1/1000.0) == int($date2/1000.0);
  }elsif($dupeMode eq $DUPE_MODE_FUZZY){
    my $absDiffMillis = $date1 > $date2 ? $date1 - $date2 : $date2 - $date1;
    return $absDiffMillis < $fuzzyDupeMillis;
  }else{
    die "ERROR: unknown DUPE_MODE $dupeMode\n";
  }
}

&main(@ARGV);
