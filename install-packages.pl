#!/usr/bin/perl
use strict;
use warnings;

system 'n9', '-s', 'apt-get', 'update';

my @packages = qw( bash bash-completion python parted );
for my $pkg(@packages){
  system 'n9', '-s', 'apt-get', 'install', $pkg;
}
