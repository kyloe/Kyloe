#!/usr/bin/perl
package Kyloe::Service;

# A totally abstract class that defines methods for services

# 1. is ISA Kyloe::SaneRoster::Service
# 2. It 'run()'
#

sub import {
    push @{caller().'::ISA'}, __PACKAGE__;
	}

sub run {
	die "run() not implemented";
}
