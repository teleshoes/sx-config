#!/usr/bin/perl
use strict;
use warnings;

my $REPO_DIR = "$ENV{HOME}/Code/sx/backup/backup-contacts/repo";

sub main(@){
  chdir $REPO_DIR;
  $ENV{PWD} = $REPO_DIR;

  my @contacts;
  my @lines = `cat contacts.vcf`;
  my $cur = undef;
  for my $line(@lines){
    $cur = '' if not defined $cur;
    $cur .= $line;
    if($line =~ /END:VCARD\s*$/){
      push @contacts, $cur;
      $cur = undef;
    }
  }
  push @contacts, $cur if defined $cur;

  my %contacts;
  for my $contact(@contacts){
    my ($first, $last, $other, $fullName, $num);
    if($contact =~ /^FN:(.+)$/m){
      $fullName = $1;
    }
    my $segRe = '(?:[^;\\\\]|\\\\;)*';
    if($contact =~ /^N:($segRe);($segRe);(.*)/m){
      ($last, $first, $other) = ($1, $2, $3);
    }
    if($contact =~ /^TEL.*(\d+)/m){
      $num = $1;
    }

    my $name;
    if(defined $fullName){
      $name = $fullName;
    }elsif(defined $first and defined $last){
      $name = "$first $last";
    }elsif(defined $first){
      $name = $first;
    }elsif(defined $last){
      $name = $last;
    }elsif(defined $other){
      $name = $other;
    }else{
      $name = "unknown";
    }
    $name =~ s/^\s*//;
    $name = lc $name;

    $num = "" if not defined $num;
    my $sortKey = "$name|$num|$contact";
    $contacts{$sortKey} = $contact;
  }

  open FH, "> contacts.vcf";
  for my $sortKey(sort keys %contacts){
    print FH $contacts{$sortKey};
  }
  close FH;
}

&main(@ARGV);
