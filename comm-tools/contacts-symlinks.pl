#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Spec qw(abs2rel);

sub relSymlink($$);
sub getContactsFromVcf($);
sub getVcardsFromVcf($);
sub getContactsFromVcard($);
sub formatContactName($);
sub formatNumberUSA($);
sub run(@);
sub runQuiet(@);

my $validFileTypes = join '|', qw(sms call);

my $usage = "Usage:
  $0 VCF_FILE FILE_TYPE SRC_DIR DEST_DIR
    create symlinks with filenames containing the names of contacts
    also makes a symlink with just the number

    symlink files named:
      \"<SRC_DIR>/<PHONE_NUMBER>.<FILE_TYPE>\"
    to:
      \"<DEST_DIR>/<VCF_NAME>-<VCF_NUMBER>.<FILE_TYPE>\"
    and also to:
      \"<DEST_DIR>/<PHONE_NUMBER>.<FILE_TYPE>\"

  VCF_FILE      path to the contacts VCF file
  FILE_TYPE     one of [$validFileTypes]
  SRC_DIR       path to the dir containing comm files
  DEST_DIR      path to place newly created contacts symlinks

  PHONE_NUMBER  phone number prefixing the comm file name
                  digits and plus signs only, all other files are ignored
  VCF_NUMBER    formatted number from VCF file
                  all characters except numbers and plus signs are discarded
  VCF_NAME      formatted contact name from the VCF file
                  \"'s\" followed by non-alphanumeric chars are replaced with \"s\"
                  groups of non-alphanumber chars are replaced with \"_\"
                  contains only letters, numbers, and underscores
";

sub main(@){
  die $usage if @_ != 4;
  my ($vcfFile, $fileType, $srcDir, $destDir) = @_;

  if($fileType !~ /^($validFileTypes)$/){
    die "invalid file type (must be one of $validFileTypes): $fileType\n";
  }
  die "could not find VCF file: $vcfFile\n" if not -f $vcfFile;
  die "not a directory: $srcDir\n" if not -d $srcDir;
  die "not a directory: $destDir\n" if not -d $destDir;

  runQuiet "rm", "-f", glob "$destDir/*.$fileType";

  my $contacts = getContactsFromVcf $vcfFile;
  my @srcFiles = glob "$srcDir/*.$fileType";
  my $countNumberSymlinks = 0;
  my $countNameSymlinks = 0;
  for my $srcFile(@srcFiles){
    if($srcFile =~ /^.*\/([0-9+]+)\.$fileType$/){
      my $num = $1;
      my $contact = $$contacts{$num};
      if(defined $contact){
        my $contactName = formatContactName $contact;
        relSymlink $srcFile, "$destDir/$contactName-$num.$fileType";
        $countNameSymlinks++;
      }
      relSymlink $srcFile, "$destDir/$num.$fileType";
      $countNumberSymlinks++;
    }
  }
  print "created $countNumberSymlinks unmodified by-number symlinks\n";
  print "created $countNameSymlinks by-contact-name symlinks\n";
}

sub relSymlink($$){
  my ($srcFile, $destFile) = @_;
  $srcFile = abs_path $srcFile;
  $destFile = abs_path $destFile;
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
    if($line =~ /^TEL;/){
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
