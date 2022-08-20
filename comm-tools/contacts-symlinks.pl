#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
use Date::Format qw(time2str);
use File::Spec qw(abs2rel);

sub relSymlink($$);
sub getContactsFromVcf($);
sub getVcardsFromVcf($);
sub getContactsFromVcard($);
sub formatContactName($);
sub formatNumberUSA($);
sub run(@);
sub runQuiet(@);

my $CMD_TYPE_SMS = "SMS";
my $CMD_TYPE_CALL = "CALL";
my $CMD_TYPE_MMS = "MMS";
my $CMD_TYPE_MMSPIX = "MMSPIX";
my @CMD_TYPES = ($CMD_TYPE_SMS, $CMD_TYPE_CALL, $CMD_TYPE_MMS, $CMD_TYPE_MMSPIX);

my %cmdTypeArgs = (
  $CMD_TYPE_SMS => join("|", qw(--sms)),
  $CMD_TYPE_CALL => join("|", qw(--call)),
  $CMD_TYPE_MMS => join("|", qw(--mms)),
  $CMD_TYPE_MMSPIX => join("|", qw(--mmspix --pix --mms-pix)),
);

my @imgExts = qw(jpg jpeg png bmp);
my $okImgExts = join "|", @imgExts;

my $validCmdTypes = join "|", sort values %cmdTypeArgs;

my $usage = "Usage:
  $0 -h|--help
    show this message

  $0 [OPTS] CMD_TYPE VCF_FILE SRC_DIR DEST_DIR
    create symlinks with filenames containing the names of contacts,
      or symlinks with just the number if number is not found in the VCF

  CMD_TYPE      $validCmdTypes
    $cmdTypeArgs{$CMD_TYPE_SMS}
      symlink files named:
        \"<SRC_DIR>/<PHONE_NUMBER>.sms\"
      to:
        \"<DEST_DIR>/<CONTACT_FORMAT>.sms\"

    $cmdTypeArgs{$CMD_TYPE_CALL}
      symlink files named:
        \"<SRC_DIR>/<PHONE_NUMBER>.call\"
      to:
        \"<DEST_DIR>/<CONTACT_FORMAT>.call\"

    $cmdTypeArgs{$CMD_TYPE_MMS}
      symlink directories named:
        \"<SRC_DIR>/<TIMESTAMP>_<NUMBER_LIST>_<DIRECTION>_<MSG_ID>\"
      to:
        \"<DEST_DIR>/<CONTACT_FORMAT>/<TIMESTAMP_FMT>_<DIRECTION>_<MSG_ID>\"

    $cmdTypeArgs{$CMD_TYPE_MMSPIX}
      symlink files named:
        \"<SRC_DIR>/<TIMESTAMP>_<NUMBER_LIST>_<DIRECTION>_<MSG_ID>/<FILE_PREFIX>.<IMG_EXT>\"
      to:
        \"<DEST_DIR>/<CONTACT_FMT>/<TIMESTAMP_FMT>_<DIRECTION>_<MSG_ID>_<FILE_PREFIX>.<IMG_EXT>\"

  OPTS
    -r | -f | --rebuild | --slow | --force
      clear DEST_DIR, removing all symlinks first, before creating new
      (this is the default)

    --no-rebuild | --quick
      do not delete existing symlinks, and skip symlink creation if target exists

  VCF_FILE      path to the contacts VCF file
  SRC_DIR       path to the dir containing comm files
  DEST_DIR      path to place newly created contacts symlinks

  PHONE_NUMBER  phone number in the filename (digits and plus signs only)
  NUMBER_LIST   a list of \"<PHONE_NUMBER>\", joined with hyphens (only first is used)
  CONTACT_FMT   either \"<VCF_NAME>-<NUMBER_FMT>\", or \"<NUMBER_FMT>\" if not found in VCF
  NUMBER_FMT    same as \"<PHONE_NUMER>\" except US country code is omitted if present
  VCF_NAME      formatted contact name from the VCF file
                  \"'s\" followed by non-alphanumeric chars are replaced with \"s\"
                  groups of non-alphanumber chars are replaced with \"_\"
                  contains only letters, numbers, and underscores
  TIMESTAMP     milliseconds since epoch
  TIMESTAMP_FMT <TIMESTAMP>, formatted as \"YYYYmmdd-HHMMSS\"
                  using `date --date @<TIMESTAMP> +%Y%m%d-%H%M%S`
  DIRECTION     INC, OUT, or NTF
";

sub main(@){
  my $cmdType;
  my $vcfFile;
  my $srcDir;
  my $destDir;
  my $rebuild = 1;
  while(@_ > 0){
    my $arg = shift @_;
    if($arg =~ /^(-h|--help)$/){
      print $usage;
      exit 0;
    }elsif($arg =~ /^(-r|-f|--rebuild|--slow|--force)$/){
      $rebuild = 1;
    }elsif($arg =~ /^(--no-rebuild|--quick)$/){
      $rebuild = 0;
    }elsif(not defined $cmdType){
      for my $type(@CMD_TYPES){
        if($arg =~ /^(?:$cmdTypeArgs{$type})$/){
          $cmdType = $type;
        }
      }
      if(not defined $cmdType){
        die "$usage\nERROR: invalid CMD_TYPE \"$cmdType\" (must be one of $validCmdTypes)\n";
      }
    }elsif(not defined $vcfFile){
      $vcfFile = $arg;
      if(not -f $vcfFile){
        die "$usage\nERROR: VCF_FILE not a file \"$vcfFile\"\n";
      }
    }elsif(not defined $srcDir){
      $srcDir = $arg;
      if(not -d $srcDir){
        die "$usage\nERROR: SRC_DIR not a directory \"$srcDir\"\n";
      }
    }elsif(not defined $destDir){
      $destDir = $arg;
      if(not -d $destDir){
        die "$usage\nERROR: DEST_DIR not a directory \"$destDir\"\n";
      }
    }else{
      die "$usage\nERROR: unknown arg $arg\n";
    }
  }

  die "$usage\nERROR: missing CMD_TYPE\n" if not defined $cmdType;
  die "$usage\nERROR: missing VCF_FILE\n" if not defined $vcfFile;
  die "$usage\nERROR: missing SRC_DIR\n" if not defined $srcDir;
  die "$usage\nERROR: missing DEST_DIR\n" if not defined $destDir;

  if($rebuild){
    if(glob "$destDir/*/*"){
      runQuiet "rm", "-f", glob "$destDir/*/*";
    }
    if(glob "$destDir/*/"){
      runQuiet "rmdir", glob "$destDir/*/";
    }
    if(glob "$destDir/*"){
      runQuiet "rm", "-f", glob "$destDir/*";
    }
  }

  my $contacts = getContactsFromVcf $vcfFile;
  my @srcFileEntries;
  if($cmdType eq $CMD_TYPE_SMS){
    for my $file(glob "$srcDir/*.sms"){
      if($file =~ /^.*\/([0-9+]+)\.sms$/){
        push @srcFileEntries, {
          file => $file,
          number => $1,
          timestamp => undef,
          direction => undef,
          msgid => undef,
          fileprefix => undef,
          fileext => undef,
        };
      }else{
        die "malformed file: $file\n";
      }
    }
  }elsif($cmdType eq $CMD_TYPE_CALL){
    for my $file(glob "$srcDir/*.call"){
      if($file =~ /^.*\/([0-9+]+)\.call$/){
        my $srcFileEntry = {
          file => $file,
          number => $1,
          timestamp => undef,
          direction => undef,
          msgid => undef,
          fileprefix => undef,
          fileext => undef,
        };
        push @srcFileEntries, $srcFileEntry;
      }else{
        die "malformed file: $file\n";
      }
    }
  }elsif($cmdType eq $CMD_TYPE_MMS){
    for my $file(glob "$srcDir/*_*_*_*"){
      if($file =~ /^.*\/(\d+)_([0-9+]*)(?:-[0-9+]+)*_(INC|OUT|NTF)_([0-9a-f]+)$/){
        my $srcFileEntry = {
          file => $file,
          number => $2,
          timestamp => $1,
          direction => $3,
          msgid => $4,
          fileprefix => undef,
          fileext => undef,
        };
        push @srcFileEntries, $srcFileEntry;
      }else{
        die "malformed file: $file\n";
      }
    }
  }elsif($cmdType eq $CMD_TYPE_MMSPIX){
    for my $file(glob "$srcDir/*_*_*_*/*.*"){
      if($file =~ /^.*\/(\d+)_([0-9+]*)(?:-[0-9+]+)*_(INC|OUT|NTF)_([0-9a-f]+)\/(.*)\.(\w+)$/){
        my $srcFileEntry = {
          file => $file,
          number => $2,
          timestamp => $1,
          direction => $3,
          msgid => $4,
          fileprefix => $5,
          fileext => $6,
        };
        next if $$srcFileEntry{fileext} !~ /^($okImgExts)$/;
        push @srcFileEntries, $srcFileEntry;
      }else{
        die "malformed file: $file\n";
      }
    }
  }

  my $countContact = 0;
  my $countTotal = @srcFileEntries;

  for my $srcFileEntry(@srcFileEntries){
    my $number = $$srcFileEntry{number};
    $number = formatNumberUSA($number);
    $number = "+++" if length $number == 0;
    my $contact = $$contacts{$number};
    my $contactFmt;
    if(defined $contact){
      $countContact++;
      my $contactName = formatContactName $contact;
      $contactFmt = "$contactName-$number";
    }else{
      $contactFmt = "unknown-$number";
    }

    my $timestampFmt;
    if(defined $$srcFileEntry{timestamp}){
      my $timestampSex = int($$srcFileEntry{timestamp} / 1000.0);
      $timestampFmt = time2str "%Y%m%d-%H%M%S", $timestampSex;
      chomp $timestampFmt;
    }else{
      $timestampFmt = undef;
    }

    my $destFile;
    my $subdir = undef;
    if($cmdType eq $CMD_TYPE_SMS){
      $destFile = "$destDir/$contactFmt.sms";
    }elsif($cmdType eq $CMD_TYPE_CALL){
      $destFile = "$destDir/$contactFmt.call";
    }elsif($cmdType eq $CMD_TYPE_MMS){
      $subdir = "$destDir/$contactFmt";
      runQuiet "mkdir", "-p", $subdir if not -d $subdir;
      $destFile = sprintf "%s/%s_%s_%s",
        $subdir,
        $timestampFmt,
        $$srcFileEntry{direction},
        $$srcFileEntry{msgid},
        ;
    }elsif($cmdType eq $CMD_TYPE_MMSPIX){
      $subdir = "$destDir/$contactFmt";
      runQuiet "mkdir", "-p", $subdir if not -d $subdir;
      $destFile = sprintf "%s/%s_%s_%s_%s.%s",
        $subdir,
        $timestampFmt,
        $$srcFileEntry{direction},
        $$srcFileEntry{msgid},
        $$srcFileEntry{fileprefix},
        $$srcFileEntry{fileext},
        ;
    }

    if(not $rebuild){
      next if -e $destFile;
    }

    relSymlink $$srcFileEntry{file}, $destFile;

    if(defined $subdir){
      runQuiet "touch", "-r", $$srcFileEntry{file}, $subdir;
    }
  }

  print "created $countTotal total symlinks ($countContact by-name)\n";
}

sub relSymlink($$){
  my ($srcFile, $destFile) = @_;
  $srcFile = abs_path $srcFile;
  die "dest file exists: $destFile\n" if -e $destFile;
  $destFile = abs_path $destFile;
  die "dest file exists: $destFile\n" if -e $destFile;

  my $destDir = $destFile;
  $destDir =~ s/\/[^\/]*$//;
  my $relSrcFile = File::Spec->abs2rel($srcFile, $destDir);
  runQuiet "ln", "-s", $relSrcFile, $destFile;
  runQuiet "touch", "-h", "-r", $srcFile, $destFile;
}

sub getContactsFromVcf($){
  my ($vcfFile) = @_;
  my $contacts = {};
  for my $vcard(getVcardsFromVcf($vcfFile)){
    for my $c(getContactsFromVcard($vcard)){
      my $number = $$c{number};
      $$contacts{$number} = $c;
    }
  }
  return $contacts;
}

sub getVcardsFromVcf($){
  my ($vcfFile) = @_;
  my @vcards;
  if(defined $vcfFile and -e $vcfFile){
    my $vcard;
    open FH, "< $vcfFile" or die "Couldnt read $vcfFile\n";
    while(my $line = <FH>){
      $vcard .= $line;
      if($line =~ /^\s*END:VCARD\s*$/){
        push @vcards, $vcard;
        $vcard = '';
      }
    }
    close FH;
    die "stuff after last END:VCARD\n" if $vcard ne "";
  }
  return @vcards;
}

sub getContactsFromVcard($){
  my ($vcard) = @_;
  my $info = {};
  my $nums = {};
  for my $line(split /[\n\r]+/, $vcard){
    if($line =~ /^(TEL;|TEL:)/){
      my $type = undef;
      $type = 'cell' if $line =~ /TYPE=CELL/;
      $type = 'home' if $line =~ /TYPE=HOME/;
      my $num = $line;
      $num =~ s/[^0-9\+]//g;
      $$nums{$num} = $type;
    }elsif($line =~ /^N:/){
      $line =~ s/^N://;
      my @names = split /;/, $line;
      $$info{names} = \@names;
    }
  }

  my @contactNums;
  for my $num(keys %$nums){
    my %numInfo = (%$info);
    $numInfo{type} = $$nums{$num};
    my $number = formatNumberUSA $num;
    $numInfo{number} = $number;
    push @contactNums, \%numInfo;
  }
  return @contactNums;
}

sub formatContactName($){
  my ($c) = @_;
  my @names = @{$$c{names}};
  my $nameStr = join ' ', grep{$_ !~ /^\s*$/} reverse @names;
  $nameStr = lc $nameStr;
  $nameStr =~ s/'s(?![a-z0-9])/s/g;
  $nameStr =~ s/[^a-z0-9]+/_/g;
  return $nameStr;
}

sub formatNumberUSA($){
  my ($num) = @_;
  #remove everything but digits and +
  $num =~ s/[^0-9+]//g;
  #remove US country code (remove leading + and/or 1 if followed by 10 digits)
  $num =~ s/^(?:\+1|1)(\d{10})$/$1/;
  return $num;
}

sub run(@){
  print "@_\n";
  runQuiet @_;
}
sub runQuiet(@){
  system @_;
  die "error running $_[0]\n" if $? != 0;
}

&main(@ARGV);
