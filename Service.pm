#!/usr/bin/perl
package Kyloe::Service;

# A totally absract clas that defines methods for services

# 1. is ISA Kyloe::SaneRoster::Service
# 2. It can getUserList
# 3. Login
# 4. doProcessing
# 5. writeData

sub import {
    push @{caller().'::ISA'}, __PACKAGE__;
	}

sub getConfig {
	die "getConfig() not implemented";
}


sub getUserList {
	die "getUserList() not implemented";
}

sub login {
	die "login() not implemented";
}

sub doProcessing {
	die "doProcessing() not implmented";
}

sub writeData {
	die "getUserList() not implemented";
}

