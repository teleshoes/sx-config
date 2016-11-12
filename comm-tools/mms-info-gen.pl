#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(time);

my $BACKUP_DIR = "$ENV{HOME}/Code/s5/backup";
my $MMS_REPO = "$BACKUP_DIR/backup-mms/repo";
my $MY_NUMBER = `cat $BACKUP_DIR/my_number`;
chomp $MY_NUMBER;

sub parseHeader($);
sub parseBody($);
sub getAttFiles($);
sub getHardcodedToFieldByMsgDir();
sub getHardcodedDateSentByMsgDir();
sub getChecksum($$$@);
sub escapeStr($);

sub main(@){
  my $toFieldByMsgDir = getHardcodedToFieldByMsgDir();
  my $dateSentByMsgDir = getHardcodedDateSentByMsgDir();
  my @entries;
  for my $msgDir(`ls $MMS_REPO`){
    chomp $msgDir;
    next unless -d "$MMS_REPO/$msgDir";
    if($msgDir !~ /^(\d+)_/){
      die "malformed dir: $msgDir\n";
    }
    my $mtime = $1;
    my ($dateMillis, $direction, $from, @to, $subject);
    my $header = parseHeader $msgDir;
    if(defined $$toFieldByMsgDir{$msgDir}){
      $direction = "OUT";
      $dateMillis = $mtime;
      $from = $MY_NUMBER;
      @to = ($$toFieldByMsgDir{$msgDir});
      $subject = "";
    }elsif(defined $header){
      if($$header{from} =~ /$MY_NUMBER/){
        $direction = "OUT";
      }else{
        $direction = "INC";
      }
      $dateMillis = $$header{date} . "000";
      $from = $$header{from};
      @to = @{$$header{to}};
      $subject = $$header{subject};
    }else{
      die "no header file for $msgDir\n" if not defined $header;
    }
    my $body = parseBody $msgDir;

    $subject = escapeStr $subject;
    $body = escapeStr $body;

    my $dateSentMillis = $$dateSentByMsgDir{$msgDir};
    $dateSentMillis = $dateMillis if not defined $dateSentMillis;

    my @attFiles = getAttFiles $msgDir;
    my $checksum = getChecksum $msgDir, $subject, $body, @attFiles;

    my $info = "";
    $info .= "from=$from\n";
    for my $toEntry(@to){
      $info .= "to=$toEntry\n";
    }
    $info .= "dir=$direction\n";
    $info .= "date=$dateMillis\n";
    $info .= "date_sent=$dateSentMillis\n";
    $info .= "subject=\"$subject\"\n";
    $info .= "body=\"$body\"\n";
    for my $attFile(@attFiles){
      $info .= "att=$attFile\n";
    }
    $info .= "checksum=$checksum\n";
    if($msgDir !~ /_$checksum$/){
      die "$msgDir CHECKSUM=$checksum\n";
    }

    my $infoFile = "$MMS_REPO/$msgDir/info";
    open FH, "> $infoFile" or die "could not write $infoFile\n$!\n";
    print FH $info;
    close FH;
  }
}

sub parseHeader($){
  my ($msgDir) = @_;
  my @headerFiles = glob "$MMS_REPO/$msgDir/*header*";
  if(@headerFiles != 1){
    return undef;
  }
  my $headerFile = $headerFiles[0];
  my $header = `cat $headerFile`;

  my ($date, $from, @to, $subject);

  if($header =~ /^message-timestamp=(\d+)$/m){
    $date = $1;
  }elsif($header =~ /^Date (.+)$/m){
    $date = `date --date '$1' +%s`;
    chomp $date;
  }

  if($header =~ /^(?:message-from=|From )(.+)$/m){
    $from = $1;
    $from =~ s/[^0-9+]//g;
    $from =~ s/^(\+?1)(\d{10})$/$2/g;
  }

  if($header =~ /^(?:message-to=|To )(.+)$/m){
    my $toValue = $1;
    my @toEntries = split /[ ,]+/, $toValue;
    for my $toEntry(@toEntries){
      if($toEntry =~ /\@Invalid/){
        $toEntry = $MY_NUMBER;
      }
      $toEntry =~ s/[^0-9+]//g;
      $toEntry =~ s/^(\+?1)(\d{10})$/$2/g;
      push @to, $toEntry;
    }
  }

  if($header =~ /^(?:message-subject=|Subject )(.*)$/m){
    $subject = $1;
  }
  $subject = "" if not defined $subject;
  $subject = "" if $subject =~ /^\s*no[ \-_]*subject\s*$/i;

  die "missing 'date' for $headerFile\n" if not defined $date or $date !~ /^\d{10}$/;
  die "missing 'from' for $headerFile\n" if not defined $from or $from !~ /^[0-9+]+$/;
  die "missing 'to'   for $headerFile\n" if @to == 0 or $to[0] !~ /^[0-9+]+$/;

  return {
    date => $date,
    from => $from,
    to => [@to],
    subject => $subject,
  };
}

sub parseBody($){
  my ($msgDir) = @_;
  my @textFiles = glob "$MMS_REPO/$msgDir/*.txt";
  if(@textFiles == 0){
    return "";
  }elsif(@textFiles == 1){
    return `cat "$textFiles[0]"`;
  }else{
    die "more than one text file\n" if @textFiles == 0;
  }
}

sub getAttFiles($){
  my ($msgDir) = @_;
  my @attFiles = glob "$MMS_REPO/$msgDir/*";
  @attFiles = grep {-f $_ and $_ !~ /(smil\d*|txt|headers?)$/i} @attFiles;
  @attFiles = map {s/$MMS_REPO\/$msgDir\///; $_} @attFiles;
  return @attFiles;
}

sub getHardcodedToFieldByMsgDir(){
  my $toFieldByMsgDir = {};
  my $curNumber = undef;
  for my $line(`cat $BACKUP_DIR/backup-mms/bak/hardcoded-recips`){
    if($line =~ /^(\d+)$/){
      $curNumber = $1;
    }elsif($line =~ /^\s+(.+)$/){
      my $msgDir = $1;
      die "cur number is not set\n" if not defined $curNumber;
      $$toFieldByMsgDir{$msgDir} = $curNumber;
    }
  }
  return $toFieldByMsgDir;
}

sub getHardcodedDateSentByMsgDir(){
  my $dateSentByMsgDir = {};
  for my $line(`cat $BACKUP_DIR/backup-mms/bak/hardcoded-datesent`){
    if($line =~ /^(.+) date_sent=(\d+)$/){
      my ($msgDir, $dateSent) = ($1, $2);
      $$dateSentByMsgDir{$msgDir} = $dateSent;
    }else{
      die "invalid hardcoded date-sent line: $line";
    }
  }
  return $dateSentByMsgDir;
}

sub getChecksum($$$@){
  my ($msgDir, $subject, $body, @attFiles) = @_;
  my $tmpFile = "/tmp/mms-tmp-file-" . int(time*1000);

  open TMPFH, "> $tmpFile";
  print TMPFH $subject if defined $subject;
  print TMPFH $body if defined $body;
  for my $file(sort @attFiles){
    my $filePath = "$MMS_REPO/$msgDir/$file";
    die "$filePath not found\n" if not -f $filePath;

    print TMPFH "\n$file\n";
    open INFH, "< $filePath" or die "Could not read $filePath\n$!\n";
    while(my $line = <INFH>){
      print TMPFH $line;
    }
    close INFH;
  }
  close TMPFH;
  my $md5sum = `md5sum $tmpFile`;
  system "rm", $tmpFile;
  if($md5sum =~ /^([0-9a-f]{32})\s+/){
    return $1;
  }else{
    die "invalid md5sum: $md5sum\n";
  }
}

sub escapeStr($){
  my ($str) = @_;
  $str =~ s/&/&amp;/g;
  $str =~ s/\\/&backslash;/g;
  $str =~ s/\n/\\n/g;
  $str =~ s/\r/\\r/g;
  $str =~ s/"/\\"/g;
  $str =~ s/&backslash;/\\\\/g;
  $str =~ s/&amp;/&/g;
  return $str;
}

&main(@ARGV);
