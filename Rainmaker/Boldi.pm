#!/usr/bin/perl
package RainMaker::Boldi;

use strict;
use warnings;

use WWW::Mechanize;
use Data::Dumper;
use Config::General;

#-------------------------------------------------------------------------------------
# Creates a new stub object
#-------------------------------------------------------------------------------------


sub new
	{
	my $class = shift;   # Determine the class for the oject to create
	my $staffid = shift;
	my $password = shift;

	my $obj = {'staffid'=> $staffid, 'password'=> $password} ;        # Instantiate a generic empty object
	
	bless $obj, $class;  # 'bless' this new generic object into the desired class
	
	my $conf = new Config::General('/var/services/homes/ian/CloudStation/Projects/Rainmaker/bin/rm/roster.cnf');

	my %hash = $conf->getall();
	$obj->{'config'} = \%hash;
	
	
	$obj->{MECH} = WWW::Mechanize->new();		# The robot
	
	
	return $obj;         # Return our newly blessed and loaded object
	}


sub login
	{
	my $self = shift;
	$self->{MECH}->credentials($self->{'config'}->{'planned'}->{'boldiUser'},$self->{'config'}->{'planned'}->{'boldiPassword'});
	$self->{MECH}->get($self->{'config'}->{'planned'}->{'boldiLogin'});
	}

sub submitRoster
	{
	my $self = shift;
	my $filename = shift;
	$self->{MECH}->form_number(0);
	$self->{MECH}->field("userfile", $filename);
	$self->{MECH}->click_button(name => 'osxwin');
	$self->{VCAL} = $self->{MECH}->content();
	}



sub dumpRoster
	{
	my $self=shift;
	return $self->{VCAL};
	}

1;