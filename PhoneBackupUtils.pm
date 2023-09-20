package PhoneBackupUtils;
use warnings;
use strict;
require Exporter;

use Time::HiRes qw(time);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our @EXPORT = qw(
  getIpmagicBlockDevUUID
  nowMillis
  mtime
  md5
  run runQuiet
  tryrun tryrunQuiet
  runRetry runRetryQuiet
  readProc readProcRetry
  readProcLines readProcLinesRetry
  runCmd
);

sub getIpmagicBlockDevUUID($$){
  my ($ipmagicName, $blockDev) = @_;
  my $devUUID = `ipmagic $ipmagicName -u root lsblk $blockDev -n -o UUID`;
  chomp $devUUID;
  if($devUUID =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/){
    return $devUUID;
  }else{
    return undef;
  }
}

sub nowMillis(){
  return int(time * 1000.0 + 0.5);
}

sub mtime($){
  my ($file) = @_;
  my @stat = stat $file;
  return $stat[9];
}

sub md5($){
  my ($file) = @_;
  die "ERROR: could not find file $file\n" if not -e $file;
  my $md5 = `md5sum "$file"`;
  if($md5 =~ /^([0-9a-f]{32})\s/){
    return $1;
  }else{
    die "ERROR: could not md5sum file $file\n";
  }
}

sub run(@){
  return runCmd({printCmd => 1, failOnError => 1}, @_);
}
sub runQuiet(@){
  return runCmd({printCmd => 0, failOnError => 1}, @_);
}
sub tryrun(@){
  return runCmd({printCmd => 1, failOnError => 0}, @_);
}
sub tryrunQuiet(@){
  return runCmd({printCmd => 0, failOnError => 0}, @_);
}

sub runRetry($@){
  my ($timeout, @cmd) = @_;
  die "ERROR: retry missing timeout\n" if $timeout !~ /^\d+$/;
  return runCmd({printCmd => 1, failOnError => 1,
    retryAttempts  => 3, timeoutSeconds => $timeout}, @cmd);
}
sub runRetryQuiet($@){
  my ($timeout, @cmd) = @_;
  die "ERROR: retry missing timeout\n" if $timeout !~ /^\d+$/;
  return runCmd({printCmd => 0, failOnError => 1,
    retryAttempts => 3, timeoutSeconds => $timeout}, @cmd);
}

sub readProc(@){
  return runCmd({printCmd => 0, failOnError => 1, readProc => 1}, @_);
}
sub readProcRetry($@){
  my ($timeout, @cmd) = @_;
  die "ERROR: retry missing timeout\n" if $timeout !~ /^\d+$/;
  return runCmd({printCmd => 0, failOnError => 1, readProc => 1,
    retryAttempts => 3, timeoutSeconds => $timeout}, @cmd);
}

sub readProcLines(@){
  my $stdout = runCmd({printCmd => 0, failOnError => 1, readProc => 1}, @_);
  my @lines = split /\r\n|\n/, $stdout;
  return @lines;
}
sub readProcLinesRetry(@){
  my ($timeout, @cmd) = @_;
  die "ERROR: retry missing timeout\n" if $timeout !~ /^\d+$/;
  my $stdout = runCmd({printCmd => 0, failOnError => 1, readProc => 1,
    retryAttempts => 3, timeoutSeconds => $timeout}, @cmd);
  my @lines = split /\r\n|\n/, $stdout;
  return @lines;
}



sub runCmd($@){
  my ($config, @cmd) = @_;

  my $conf = {
    wrapShell      => 0,
    printCmd       => 0,
    readProc       => 0,
    failOnError    => 1,
    retryAttempts  => 0,
    timeoutSeconds => 0,
    %$config,
  };

  for my $key(sort keys %$conf){
    if($key !~ /^(wrapShell|printCmd|readProc|failOnError|retryAttempts|timeoutSeconds)$/){
      die "ERROR: unknown run conf opt $key\n";
    }
  }

  if($$conf{wrapShell}){
    @cmd = ("sh", "-c", "@cmd");
  }
  if($$conf{timeoutSeconds} > 0){
    @cmd = ("timeout", $$conf{timeoutSeconds}, @cmd);
  }

  print "@cmd\n" if $$conf{printCmd};

  my $exitCode;
  my $error;
  my $stdout;
  my $retryAttempts = $$conf{retryAttempts};
  while(1){
    if($$conf{readProc}){
      my $cmdFH;
      if(open $cmdFH, "-|", @cmd){
        $stdout = join '', <$cmdFH>;
        close $cmdFH;
        $exitCode = $? >> 8;
        $error = $!;
      }else{
        $stdout = "";
        $exitCode = -1;
        $error = $1;
      }
    }else{
      system @cmd;
      $exitCode = $? >> 8;
      $error = $!;
    }

    if($exitCode != 0){
      my $timedOutMsg = "timedout=no";
      if($$conf{timeoutSeconds} > 0 and $exitCode == 124){
        $timedOutMsg = "timedout=yes";
      }

      if($retryAttempts > 0){
        $retryAttempts--;
        print "COMMAND FAILED ($timedOutMsg): @cmd\nRETRYING IN 3s...\n";
        sleep 3;
      }else{
        last;
      }
    }else{
      last;
    }
  }

  if($exitCode != 0 and $$conf{failOnError}){
    die "\n\nERROR: '@cmd' failed\n$error\n";
  }

  if($$conf{readProc}){
    return $stdout;
  }else{
    return $exitCode;
  }
}

1;
