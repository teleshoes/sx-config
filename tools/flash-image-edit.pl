#!/usr/bin/perl
use strict;
use warnings;
use IPC::Run qw(start finish);

my $SRC_SPARSE_IMG = "sailfish.img001";
my $BAK_SPARSE_IMG = "orig-sailfish.img001.bak";
my $DEST_RAW_IMG = "sfos_lvm_raw.img";

my $ALTERNATE_PRODUCT_CODES = {
  H8314 => [qw(SO-05K)],
};
my $ALTERNATE_PRODUCT_CODES_FMT = join(", ",
  map {"[$_ => " . join(" | ", @{$$ALTERNATE_PRODUCT_CODES{$_}}) . "]"}
  sort keys %$ALTERNATE_PRODUCT_CODES
);

sub editSailfishImg();
sub editFlashSh();
sub editFlashConfigSh();
sub editAutologinGuestfish($);
sub createRawImg();
sub restoreSparseImg();
sub startGuestfish(@);
sub stopGuestfish($);
sub writeCmd($$);
sub readOut($);
sub grepFile($$);
sub nowMillis();
sub run(@);
sub runQuiet(@);

sub main(@){
  print "\n\n########################################\n"
    . "### editing flash.sh:\n"
    . "###   -allow alternate device product codes: $ALTERNATE_PRODUCT_CODES_FMT\n"
    . "###   -add '-S 512k' to oem flashing args\n"
  ;
  editFlashSh();

  print "\n\n########################################\n"
    . "### editing flash-config.sh:\n"
    . "###   -allow any version OEM image, e.g.: '*_v9a_*' => '*_*'\n"
  ;
  editFlashConfigSh();

  print "\n\n########################################\n"
    . "### editing sailfish root LVM image\n"
    . "###  -change user defaultuser => nemo\n"
    . "###  -remove encrypt-home marker to prevent LUKS encrytpion\n"
  ;
  editSailfishImg();

  print "\n\n########################################\n"
    . "### updating md5.list\n"
  ;
  updateMd5("md5.lst", "flash.sh", "flash-config.sh", "hybris-boot.img", $SRC_SPARSE_IMG);

  print "\n\n########################################\n"
    . "### done\n"
  ;
}

sub editSailfishImg(){
  print "\n# creating raw img from sparse img\n";
  createRawImg();

  my $tmpDir = "$ENV{PWD}/guestfs-cache";
  system "mkdir", "-p", $tmpDir;
  $ENV{TMPDIR} = $tmpDir;

  print "\n# starting guestfish\n";
  my $gf = startGuestfish qw(
    guestfish
      --rw
      --blocksize=4096
      -a sfos_lvm_raw.img
      -m /dev/mapper/sailfish-root:/:noatime:ext4
  );

  print "\n# waiting for run+mount (should take between 2s - 60s)\n";
  ready($gf);
  print "ready!\n";

  print "\n# ensuring root filesystem fills available space\n";
  writeCmd($gf, "resize2fs /dev/mapper/sailfish-root");

  print "\n# editing autologin\n";
  editAutologinGuestfish($gf);

  print "\n# remove encrypt-home, if present\n";
  writeCmd($gf, "rm-f /var/lib/sailfish-device-encryption/encrypt-home");

  writeCmd($gf, "sync");
  ready($gf);

  print "\n# guestfish cleanup + exit\n";
  stopGuestfish($gf);
  run "sudo", "rm", "-r", $tmpDir;

  print "\n# creating sparse img from raw img\n";
  restoreSparseImg();
}

sub updateMd5($@){
  my ($checkListFile, @updatedFiles) = @_;

  for my $f(@updatedFiles){
    next if not -f $f;
    my $md5 = `md5sum $f`;
    chomp $md5;
    die "ERROR: could not get md5 for $f\n" if $md5 !~ /^[0-9a-f]{32}\s*$f$/;

    run("sed", "-i", "s/^[0-9a-f]*\\s*$f\$/$md5/", $checkListFile);
  }
}

sub editFlashSh(){
  if(not -e "orig-flash.sh"){
    run "mv", "flash.sh", "orig-flash.sh";
  }
  die "ERROR: missing orig-flash.sh\n" if not -f "orig-flash.sh";
  run "rm", "-f", "flash.sh";
  run "cp", "-a", "orig-flash.sh", "flash.sh";

  my $found = 0;
  for my $origCode(sort keys %$ALTERNATE_PRODUCT_CODES){
    my @altCodes = @{$$ALTERNATE_PRODUCT_CODES{$origCode}};
    if(grepFile($origCode, "flash.sh")){
      $found = 1;
      print "# editing flash.sh for product code $origCode => (@altCodes)\n";
      my $searchPtrn;
      my $replPtrn = "\\\\(" . join("\\\\|", $origCode, @altCodes) . "\\\\)";
      run "sed", "-i", "-E",
        "s/grep -e \"$origCode\"/grep -e \"$replPtrn\"/",
        "flash.sh";
    }
  }
  print "# no alternate device product codes added\n" if not $found;


  if(grepFile(".-S 512k flash", "flash.sh")){
    print "skipping already present '-S 512k flash'\n";
  }else{
    print "editing flash.sh to add -S 512k to flash_blob\n";
    run "sed", "-i", "-E",
      "s/flash \"\\\$partition\" \"\\\$b\"/-S 512k \\0/",
      "flash.sh";
  }
}

sub editFlashConfigSh(){
  if(not -e "flash-config.sh"){
    print "# no flash-config.sh, skipping\n";
    return;
  }

  if(not -e "orig-flash-config.sh"){
    run "mv", "flash-config.sh", "orig-flash-config.sh";
  }
  die "ERROR: missing orig-flash-config.sh\n" if not -f "orig-flash-config.sh";
  run "rm", "-f", "flash-config.sh";
  run "cp", "-a", "orig-flash-config.sh", "flash-config.sh";

  #replace '_v9a_' => '_'
  run "sed", "-i", "-E",
    "s/(flash_blob.*)(_v[a-zA-Z0-9]*_)/\\1_/",
    "flash-config.sh",
  ;
}

sub editAutologinGuestfish($){
  my ($gf) = @_;

  if(-e "start-autologin"){
    run "rm", "start-autologin";
  }

  writeCmd($gf, "stat /usr/lib/startup/start-autologin");
  my $stat = readOut($gf);
  my $mode = $1 if $stat =~ /^mode: (\d+)$/m;
  my $uid = $1 if $stat =~ /^uid: (\d+)$/m;
  my $gid = $1 if $stat =~ /^gid: (\d+)$/m;
  if(not defined $mode or not defined $uid or not defined $gid){
    die "ERROR: stat failed on start-autologin\n";
  }

  writeCmd($gf, "copy-out /usr/lib/startup/start-autologin .");
  ready($gf);

  if(-e "start-autologin"){
    my @repls =(
      's/# No system user.*/\0### APPLIED HACK: defaultuser => nemo/',
      's/useradd -g defaultuser \(.*\) defaultuser/useradd -g nemo \1 nemo/',
      's/groupadd \(.*\) defaultuser/groupadd \1 nemo/',
    );
    for my $repl(@repls){
      run "sed", "-i", $repl, "start-autologin";
    }
  }else{
    die "ERROR: copy-out start-autologin failed\n";
  }

  writeCmd($gf, "copy-in start-autologin /usr/lib/startup/");
  ready($gf);

  writeCmd($gf, "chmod $mode /usr/lib/startup/start-autologin");
  ready($gf);

  writeCmd($gf, "chown $uid $gid /usr/lib/startup/start-autologin");
  ready($gf);

  writeCmd($gf, "sync");
  ready($gf);

  writeCmd($gf, "cat /usr/lib/startup/start-autologin");
  my $res = readOut($gf);
  if($res =~ /useradd.*-g nemo.*nemo/){
    print "  #OK: start-autologin contains useradd -g nemo nemo\n";
  }else{
    die "ERROR: expected 'useradd -g nemo nemo' in start-autologin\n";
  }

  run "rm", "start-autologin";
}

sub createRawImg(){
  if(not -e $BAK_SPARSE_IMG){
    run "mv", $SRC_SPARSE_IMG, $BAK_SPARSE_IMG;
  }
  die "ERROR: missing $BAK_SPARSE_IMG\n" if not -f $BAK_SPARSE_IMG;
  run "rm", "-f", $SRC_SPARSE_IMG;

  if(-e $DEST_RAW_IMG){
    run "rm", $DEST_RAW_IMG;
  }

  run "simg2img", $BAK_SPARSE_IMG, $DEST_RAW_IMG;

  if(not -f $DEST_RAW_IMG){
    die "ERROR: simg2img failed\n";
  }
}

sub restoreSparseImg(){
  my $nowMillis = nowMillis();
  die "ERROR: $SRC_SPARSE_IMG already exists\n" if -e $SRC_SPARSE_IMG;

  run "img2simg", $DEST_RAW_IMG, $SRC_SPARSE_IMG;
  if(not -f $SRC_SPARSE_IMG){
    die "ERROR: img2simg failed\n";
  }

  run "rm", $DEST_RAW_IMG;
}

sub startGuestfish(@){
  my @cmd = @_;

  my ($inputH, $outputH);
  my $gf = {
    h => undef,
    in => $inputH,
    out => $outputH,
  };

  $$gf{h} = start \@cmd, \$$gf{in}, \$$gf{out};

  return $gf;
}

sub stopGuestfish($){
  my ($gf) = @_;

  writeCmd($gf, "umount /");
  sleep 3;

  writeCmd($gf, "shutdown");
  sleep 3;

  writeCmd($gf, "quit");
  sleep 3;

  $$gf{h}->finish();
}

sub ready($){
  my ($gf) = @_;
  writeCmd($gf, "ls /");
  my $lsRoot = readOut($gf);
  if($lsRoot !~ /^usr$/m){
    die "ERROR: `ls /` did not list /usr\n";
  }
}

sub writeCmd($$){
  my ($gf, $cmd) = @_;
  print "  #guestfish-cmd: $cmd\n";
  $$gf{in} .= "$cmd\n";
  $$gf{h}->pump_nb() until length $$gf{in} == 0;
}
sub readOut($){
  my ($gf) = @_;
  $$gf{h}->pump_nb() until length $$gf{out} > 0;
  my $s = "$$gf{out}";
  $$gf{out} = '';
  return $s;
}

sub grepFile($$){
  my ($ptrn, $file) = @_;
  system "grep", "--silent", $ptrn, $file;
  if($? == 0){
    return 1;
  }else{
    return 0;
  }
}

sub nowMillis(){
  return int(time * 1000.0 + 0.5);
}

sub run(@){
  print "@_\n";
  runQuiet(@_);
}

sub runQuiet(@){
  system @_;
  if($? != 0){
    die "ERROR: \"@_\" failed\n";
  }
}

&main(@ARGV);
