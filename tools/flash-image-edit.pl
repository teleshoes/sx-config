#!/usr/bin/perl
use strict;
use warnings;
use IPC::Run qw(start finish);

my $SRC_SPARSE_IMG = "sailfish.img001";
my $DEST_RAW_IMG = "sfos_lvm_raw.img";

sub editFlashSh();
sub createRawImg();
sub restoreSparseImg();
sub startGuestfish(@);
sub writeCmd($$);
sub readOut($);
sub nowMillis();
sub run(@);

sub main(@){
  editFlashSh();

  createRawImg();

  print "\n\n### starting guestfish\n";
  my $gf = startGuestfish qw(
    guestfish
      --rw
      --blocksize=4096
      -a sfos_lvm_raw.img
      -m /dev/mapper/sailfish-root:/:noatime:ext4
  );

  print "\n\n### waiting for run+mount (should take between 2s - 60s)\n";
  ready($gf);
  print "ready!\n";

  ############
  print "\n\n### editing the root image\n";

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
    run "sed", "-i", "s/defaultuser/nemo/g", "start-autologin";
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
  ############

  print "\n\n### guestfish cleanup + exit\n";
  writeCmd($gf, "umount /");
  sleep 3;

  writeCmd($gf, "shutdown");
  sleep 3;

  writeCmd($gf, "quit");
  sleep 3;

  $$gf{h}->finish();

  restoreSparseImg();

  print "\n\n### updating md5.list\n";
  updateMd5("md5.lst", "flash.sh", $SRC_SPARSE_IMG);

  print "\n\n### done\n";
}

sub updateMd5($@){
  my ($checkListFile, @updatedFiles) = @_;

  for my $f(@updatedFiles){
    my $md5 = `md5sum $f`;
    chomp $md5;
    die "ERROR: could not get md5 for $f\n" if $md5 !~ /^[0-9a-f]{32}\s*$f$/;

    run("sed", "-i", "s/^[0-9a-f]*\\s*$f\$/$md5/", $checkListFile);
  }
}

sub editFlashSh(){
  print "\n\n### editing flash.sh for SO-05K\n";
  run "sed", "-i", "-E",
    "s/grep -e \"[^\"]*H8314[^\"]*\"/grep -e \"\\\\(H8314\\\\|SO-05K\\\\)\"/",
    "flash.sh";
}

sub createRawImg(){
  print "\n\n### creating raw img from sparse img\n";
  if(-e $DEST_RAW_IMG){
    run "rm", $DEST_RAW_IMG;
  }

  if(not -f $SRC_SPARSE_IMG){
    die "ERROR: could not find sailfish.img001\n";
  }

  run "simg2img", $SRC_SPARSE_IMG, $DEST_RAW_IMG;

  if(not -f $DEST_RAW_IMG){
    die "ERROR: simg2img failed\n";
  }
}

sub restoreSparseImg(){
  print "\n\n### creating sparse img from raw img\n";
  my $nowMillis = nowMillis();
  run "mv", $SRC_SPARSE_IMG, "sailfish.img001.bak.$nowMillis";

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

sub nowMillis(){
  return int(time * 1000.0 + 0.5);
}

sub run(@){
  print "@_\n";
  system @_;
  if($? != 0){
    die "ERROR: \"@_\" failed\n";
  }
}

&main(@ARGV);
