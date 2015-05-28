#!/usr/bin/perl
package Kyloe::CWP::Connector;

use CGI;
use WWW::Mechanize;
use HTML::TreeBuilder; 
use HTTP::Cookies;
use Data::Dumper;
use Class::Date qw(:errors date localdate gmdate now -DateParse -EnvC);
use JSON;  
#use IO::Socket::SSL qw();
use strict;
use warnings;
use XML::Simple;
use Kyloe::ICS;


my $specialDuties = {'DO'=>'Day Off','RDO'=>'Rest Day','LV'=>'Leave','JUR'=>'Jury Duty','RST'=>'Rest Day','N/A'=>'Not Available','OFF'=>'OFF'};

#-------------------------------------------------------------------------------------
# Creates a new connector
#-------------------------------------------------------------------------------------

BEGIN { $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 }


sub new
{
	my $class    = shift;    # Determine the class for the oject to create ok

	my $obj = {
	};                       # Instantiate a generic empty object

	bless $obj, $class; # 'bless' this new generic object into the desired class

 
	$obj->{MECH} = WWW::Mechanize->new();
	
	$obj->{MECH}->cookie_jar( HTTP::Cookies->new( file => "/home/ian/cookies.txt") );

	return $obj;    # Return our newly blessed and loaded object
}

sub login
{
	my $self = shift;
	my $staffid  = shift;
	my $password = shift;
	
	$self->{MECH}->get("https://cwp.jet2.com/CWP_WA/CWPLogin.aspx")
	   or die "Could not get login page";
	$self->{MECH}->form_name('form1') or die "Could not get form\n";
	$self->{MECH}->field( 'ctrlUserName', $staffid );
	$self->{MECH}->field( 'ctrlPassword', $password );
	$self->{MECH}->click_button( name => "btnLogin" ) or die "Could not click button\n";
	#$self->{MECH}->submit() or die "Failed to submit";  

	return 1;
}

sub getRoster
{
	my $self = shift;
	$self->{MECH}->get('https://cwp.jet2.com/CWP_WA/CWP_Window_RosterXML.aspx')
	  or die "Could not retrieve roster page";
	$self->{XML} = XML::Simple->new(SuppressEmpty => '');
	$self->{TREE} = $self->{XML}->XMLin($self->{MECH}->content());
	#print Dumper($self->{TREE});
	
	my $ics = Kyloe::ICS->new();

    my $id;
    my $event;
    my $date;
    my $uidCounter=0;
    
	foreach $event (@{$self->{TREE}->{CWPReportRoster}})
		{
		$id = $ics->add_vevent();

		$ics->add_vevent_property($id,'DESCRIPTION',$event->{'ActivityDesc'}.' - '.$event->{'STA'}.' '.$event->{'Origin'}.' '.$event->{'Destination'}.' '.$event->{'STD'});
        

        	my $date = $event->{'ActivityDate'};
        	my $year = substr $date,6,4;
	        my $month = substr $date,3,2;
        	my $day = substr $date,0,2;
        	my $hour = substr $date,11,2;
        	my $min = substr $date,14,2;
        	my $arrHour;
        	my $arrMin;
        	my $depHour;
        	my $depMin;
			my $arrTime;
			
		if ($event->{'CheckInTime'})
			{
			my $ciTime = $event->{'CheckInTime'};
			my $ciHour = substr $ciTime,0,2;
			my $ciMin = substr $ciTime,3,2;
			my $ci_id = $ics->add_vevent();
			$ics->add_vevent_property($ci_id,'DESCRIPTION','Checkin');
			$ics->add_vevent_property($ci_id,'DTSTART',$year.$month.$day.'T'.$ciHour.$ciMin.'00Z');
			$ics->add_vevent_property($ci_id,'DTEND',$year.$month.$day.'T'.$hour.$min.'00Z');
			$ics->add_vevent_property($ci_id,'UID',"saneRoster-" . $event->{IdEmpNo}.'-'.$self->mynow().'-'.$uidCounter++);
			$ics->add_vevent_property($ci_id,'SUMMARY','Checkin');
			$ics->add_vevent_property($ci_id,'DTSTAMP',$self->mynow());
			}	


        
        	if ($specialDuties->{$event->{'ActivityDesc'}})
        		{
        		$arrHour = '23';
        		$arrMin = '59';        		
        		$depHour = '00';
        		$depMin = '01';
        		}
        	else
        		{
        		#No these are not the wrong way round - its a bug in CWP that we're munging
        		$arrHour = substr $event->{'STD'},0,2;
        		$arrMin = substr $event->{'STD'},3,2;        		
        		$depHour = substr $event->{'STA'},0,2;
        		$depMin = substr $event->{'STA'},3,2;
        		}

			# TODO: makedate objects for all the useful dates
			# compare start date with end date time and see if we have rolled past midnight
			# if so - add aday to end date time
			# calculate length of shift then add to start time to get end time (fer fucks sake)
			my $std_dt = Class::Date->new([$year,$month,$day,$depHour,$depMin,0],'UTC');
			my $sta_dt = Class::Date->new([$year,$month,$day,$arrHour,$arrMin,0],'UTC');

	
		if ($sta_dt < $std_dt)
			{
			$sta_dt += '1D';
			}

			
			my $start_dt = Class::Date->new([$year,$month,$day,$hour,$min,0],'UTC');
			my $end_dt = $start_dt + ($sta_dt - $std_dt); 
		

#        	$arrTime = $arrHour.$arrMin;
#        	$arrTime =~ s/://g;
        	
			
		$ics->add_vevent_property($id,'DTSTART',$start_dt->year.lz($start_dt->mon).lz($start_dt->day).'T'.lz($start_dt->hour).lz($start_dt->min).'00Z');		
		$ics->add_vevent_property($id,'DTEND',$end_dt->year.lz($end_dt->mon).lz($end_dt->day).'T'.lz($end_dt->hour).lz($end_dt->min).'00Z');			
		$ics->add_vevent_property($id,'UID',"saneRoster-" . $event->{IdEmpNo}.'-'.$self->mynow().'-'.$uidCounter++);
		$ics->add_vevent_property($id,'SUMMARY',$event->{'ActivityDesc'}.':'.$event->{'Origin'}.' '.$event->{'Destination'});
		$ics->add_vevent_property($id,'DTSTAMP',$self->mynow());
		
		}

	return $ics->as_string();
	
}




sub writeMessage
{
	my $dateStamp = shift;
	
	my $birthdayMsg = '';
	$birthdayMsg .= "BEGIN:VEVENT\n";
	$birthdayMsg .= "DTSTART:20151031T090000\n";
	$birthdayMsg .= "DTEND:20151031T235900\n";
	$birthdayMsg .= "SUMMARY: Ian's Birthday\n";
	$birthdayMsg .= "DESCRIPTION: Today is Ian's Birthday, Ian likes Red Wine, Malt Whisky and Chocolate\n";
	$birthdayMsg .= "UID:saneRoster-" .$dateStamp. "-msg\n";
	$birthdayMsg .= "DTSTAMP:" . $dateStamp . "\n";
	
	$birthdayMsg .= "END:VEVENT\n";	
	return $birthdayMsg;
}


sub writeICS  
{
	$| = 1;

	my $self = shift;
	my $para = shift;
	
	my $file = '/var/services/web/dance/public/cwp/'.$para->{staffid}.'.ics';
	#my $file = '/home/ian/cwp/'.$para->{staffid}.'.ics';
		
	if (!open (MYFILE, '>'.$file))
	{
		*MYFILE = *STDOUT;
	}
	
	print MYFILE $self->getRoster();
	}

sub mynow()
{
	my $self = shift;
	my $d    = now;
	my @date = unpack( "A4xA2xA2xA2xA2xA2", $d );
	return $date[0]
	  . $date[1]
	  . $date[2] . "T"
	  . $date[3]
	  . $date[4]
	  . $date[5];
}
	
sub lz()
{
	my $x = shift;
	if (length $x <2)
	{
		return '0'.$x;
	}
	return $x;
}
	
1;
