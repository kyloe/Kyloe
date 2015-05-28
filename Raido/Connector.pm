#!/usr/bin/perl
package Kyloe::Raido::Connector;

use JSON;
use CGI;
use WWW::Mechanize;
use HTML::TreeBuilder; 
use HTTP::Cookies;
use Data::Dumper;
use Class::Date qw(:errors date localdate gmdate now -DateParse -EnvC);

use strict;
use warnings;


my $specialDuties = {
		'SDR'=>'Self Drive - OK, we\'ve got stolen police car, a full tank of gas and we\'re wearing sunglasses ...',
		'MTG'=>'Meeting - I LOVE meetings me',
		'TAX'=>'Taxi',
		'HTL'=>'Hotel or perhaps ... Sumburgh',
		'ADM'=>'Admin',
		'FAD'=>'Flex Admin',
		'MAD'=>'Like Admin - but madder',
		'SCO'=>'Called out',
		'APT'=>'Airport Standby (ARRRGGGHHHH)',
		'SBY'=>'Standby',
		'SB1'=>'Early Standby',
		'SB2'=>'Late Standby',
		'DO'=>'Day Off - Hoorah!',
		'RDO'=>'AKA "Fly Dubai" or "BA" interview',
		'LVE'=>'Leave',
		'JUR'=>'Jury Duty (Guilty)',
		'N/A'=>'Not Available = LEAVE ME ALONE!',
		'CRM'=>'Crew Resource Management - cuddles all round',
		'DG'=>'Dangerous Goods',
		'SEC'=>'Security - Well Helllooooo ... Touchy touchy??',
		'RST'=>'ZZzzzz...',
		'SCK'=>'Sicky - yeah right ... one too many???',
		'COM'=>'COM ... Hmmm wassat?',
		'ACO'=>'Airport Call Out',
		'WDO'=>'Money money money',
		'ES'=>'Emergency and Security (I\'m so bored I may have to chew off my own arm )',
		'ASF'=>'ASF .. hmmm .. not sure ... "A Small Fish" perhaps?',
		};

my $patchedTimes = {
		'DO'=>'Day Off',
		'RDO'=>'Rest Day',
		'LVE'=>'Leave',
		'N/A'=>'Not Available = LEAVE ME ALONE!',
		'RST'=>'ZZzzzz...',
		'SCK'=>'Sicky - yeah right ... one too many???',		
};

#-------------------------------------------------------------------------------------
# Creates a new connector
#-------------------------------------------------------------------------------------



sub new
{
	my $class    = shift;    # Determine the class for the oject to create ok

	my $obj = {
	};                       # Instantiate a generic empty object

	bless $obj, $class; # 'bless' this new generic object into the desired class

 
	$obj->{MECH} = WWW::Mechanize->new();    # The robot
	
	$obj->{MECH}->cookie_jar( HTTP::Cookies->new( file => "/home/ian/cookies.txt") );
	
	$obj->{'specialDuties'} = $specialDuties;
	$obj->{'patchedTimes'} = $patchedTimes;

	return $obj;    # Return our newly blessed and loaded object
}

sub login
{
	my $self = shift;
	my $staffid  = shift;
	my $password = shift;
	
	$self->{MECH}->get("https://raido.loganair.co.uk/raido/")
	  or die "Could not get login page";
	$self->{MECH}->form_name('form1') or die "Could not get form\n";
	$self->{MECH}->field( 'txtUserName', $staffid );
	$self->{MECH}->field( 'txtPassword', $password );
	$self->{MECH}->click_button( name => "btnSub" )
	  or die "Could not click button\n";
	return 1;
}

sub getRoster
{
	my $self = shift;
	$self->{MECH}->get('https://raido.loganair.co.uk/Raido/Dialogues/HumanResources/HumanResourceMyRoster.aspx')
	  or die "Could not retrieve roster page";


	$self->{TREE} = HTML::TreeBuilder->new();
	$self->{TREE}->parse( $self->{MECH}->content() );
	$self->{TREE}->elementify();
	return 1;
}

sub post_json {
    my ($mech, $json, $url) = @_;
    my $req = HTTP::Request->new(POST => $url);
    $req->content_type('application/json; charset=UTF-8');
    $req->content($json);
    return $mech->request($req);
}

sub getNextMonth
{
	my $self = shift;
	
	
	$self->{MECH}->post('https://raido.loganair.co.uk/Raido/Dialogues/HumanResources/HumanResourceMyRoster.aspx?iframeid=Iframe0')
	  					or die "Could not retrieve roster page";

	
	my $monthURL = 'https://raido.loganair.co.uk/raido/Dialogues/HumanResources/HumanResourceMyRoster.aspx/ReloadMonths';

    $self->{MECH}->delete_header('TE');
    $self->{MECH}->add_header('Content-Type'=>'application/json; charset=UTF-8');
    $self->{MECH}->delete_header('Cookie2');
    $self->{MECH}->add_header('Accept-Encoding'=>'gzip,deflate,sdch');
    $self->{MECH}->agent_alias( 'Windows Mozilla' );
    $self->{MECH}->add_header('Origin'=>'https://raido.loganair.co.uk');
    $self->{MECH}->add_header('X-Requested-with'=>'XMLHttpRequest');
    $self->{MECH}->add_header('Referer'=>'https://raido.loganair.co.uk/raido/Dialogues/HumanResources/HumanResourceMyRoster.aspx?iframeID=Iframe0');
    $self->{MECH}->add_header('Accept'=>'application/json, text/javascript, */*; q=0.01');
    $self->{MECH}->add_header('Accept-Language'=>'en-GB,en-US;q=0.8,en;q=0.6,ru;q=0.4');

	my $m = nextMonthKludge();

	my $manString = '{ increaseordecrease: "1", lastmonth: "'.$m.'", firstmonth: "'.$m.'", ddlselectehresid: "undefined", iframe: "Iframe0" }';

    local @LWP::Protocol::http::EXTRA_SOCK_OPTS = (SendTE => 0,KeepAlive => 1);
    
    $self->{MECH}->post($monthURL,content=>$manString);

	my $js = JSON->new->utf8->decode($self->{MECH}->content());
	
	$self->{'TREE_2'} = HTML::TreeBuilder->new();
	$self->{'TREE_2'}->parse( $js->{d} ) or die "Failed to parse TREE_2\n";
#	$self->{'TREE_2'}->utf8_mode();
#	$self->{'TREE_2'}->parse( $self->{MECH}->content() ) or die "Failed to parse TREE_2\n";
	$self->{'TREE_2'}->elementify();
	
	
	return 1;
}

sub parseRoster
{
	my $self = shift;
	my $treeID = shift;
	  
#	print "Parse $treeID\n";
	
	my @entries =
	  $self->{$treeID}
	  ->look_down( _tag => "table", activityDetailId => qr/\d\d\d\d\d\d/ );

	my $n = 1;

#print "Found $#entries\n";

	foreach (@entries)
	{

		$n += 1;

		my @item = $_->look_down( _tag => 'td' );

		if ($self->{'specialDuties'}->{$item[1]->as_text()})
		{

			# Need to find the date elsewhere
			# Need to find div for this id, then find parent then find date in the first child

			my $friendCell = $self->{$treeID}->look_down(
				_tag       => "DIV",
				activityId => $_->{activitydetailid}
			);
			my $parentCell    = $friendCell->parent;
			my $dayNumberCell =
			  $parentCell->look_down( _tag => "DIV", class => "dayNumberCell" );
			my $dayNumber = $dayNumberCell->as_text;

			$self->{CAL}->{ $_->{activitydetailid} }->{'Start (UTC)'} =
			  $self->dateReWrite($dayNumber) . 'T000000';

			$self->{CAL}->{ $_->{activitydetailid} }->{'End (UTC)'} =
			  $self->dateReWrite($dayNumber) . 'T235900';

		}

		my $i;

		for ( $i = 0 ; $i < $#item ; $i += 2 )
		{
			$self->{CAL}->{ $_->{activitydetailid} }->{ $item[$i]->as_text } =
			  $item[ $i + 1 ]->as_text;
			# print 'Adding '. $_->{activitydetailid}.' : '. $item[$i]->as_text .' = '.$item[ $i + 1 ]->as_text."\n";
			# WOrk around for Raido rubbish
			# If CODE is in list of times that need 'patching' set start and end times to Local and not UTC for all day activities
			#if ($self->{'patchedTimes'}->{$item[$i]->as_text})
			#{
			#	$self->{CAL}->{ $_->{activitydetailid} }->{ 'Start (UTC)' } =~ s/Z//g;
			#	$self->{CAL}->{ $_->{activitydetailid} }->{ 'End (UTC)' } =~ s/Z//g;
			#}
		}
	}

	return 1;
}

sub dateReWrite
{

	# translate DD MONTHNAME YYYY
	# to
	# YYYYMMDD
	
	my %monthNumbers = (
		"January"   => "01",
		"February"  => "02",
		"March"     => "03",
		"April"     => "04",
		"May"       => "05",
		"June"      => "06",
		"July"      => "07",
		"August"    => "08",
		"September" => "09",
		"October"   => "10",
		"November"  => "11",
		"December"  => "12"
		);
		
	my $self       = shift;
	my $dateString = shift;

	my @date = split( / /, $dateString );
	return $date[2] . $monthNumbers{ $date[1] } . padDate( $date[0] );
}

sub dateTimeReWrite {
	my $self = shift;
	return $self->dateTimeReWriteLocal(@_).'Z';
}

sub dateTimeReWriteLocal
{

	# translate DDMMMYY HH:MM
	# to
	# YYYYMMDDTHHMMSS
	my $self       = shift;
	my $dateString = shift;

	if (!$dateString)
	{
		return '20010101T000000'; # Ooops
	}
	#print $dateString.'\n';
	if ( $dateString =~ /\d\d\d\d\d\d\d\dT\d\d\d\d\d\d/ )
	{
		return $dateString;    # Already converted
	}

	my %monthNumbers = (
		"JAN" => "01",
		"FEB" => "02",
		"MAR" => "03",
		"APR" => "04",
		"MAY" => "05",
		"JUN" => "06",
		"JUL" => "07",
		"AUG" => "08",
		"SEP" => "09",
		"OCT" => "10",
		"NOV" => "11",
		"DEC" => "12"
	);

	my @date = unpack( "A2A3A2xA2xA2", $dateString );

	return "20"
	  . $date[2]
	  . $monthNumbers{ $date[1] }
	  . $date[0] . "T"
	  . $date[3]
	  . $date[4] . "00";
}
sub writeMessage
{
	my $dateStamp = shift;
	
	my $birthdayMsg = '';
	$birthdayMsg .= "BEGIN:VEVENT\r\n";
	$birthdayMsg .= "DTSTART:20141031T090000\r\n";
	$birthdayMsg .= "DTEND:20141031T235900\r\n";
	$birthdayMsg .= "SUMMARY: Ian's Birthday\r\n";
	$birthdayMsg .= "DESCRIPTION: Today is Ian's Birthday, Ian likes Nehru Jackets, Aston Martins and Fresh Corriander\r\n";
	$birthdayMsg .= "UID:saneRoster-" .$dateStamp. "-msg\r\n";
	$birthdayMsg .= "DTSTAMP:" . $dateStamp . "\r\n";
	
	$birthdayMsg .= "END:VEVENT\r\n";	
	return $birthdayMsg;
}
sub writeICS  
{
	$| = 1;

	my $self = shift;
	my $para = shift;
	
	my $file;
	if ($para->{altfilename})
		{
		$file = $para->{altfilename};
		}
	else
		{	
		$file = '/var/services/web/dance/public/cal/'.$para->{staffid}.'.ics';
		}

	print "Generating ".$file."\n";

	if (!open (MYFILE, '>'.$file))
	{
		*MYFILE = *STDOUT;
	}
	
	print MYFILE "BEGIN:VCALENDAR\nVERSION:2.0\nMETHOD:PUBLISH\nCOMMENT: Generated by saneRoster \r\n";

	print MYFILE writeMessage($self->mynow);

	foreach my $activityid ( keys %{$self->{CAL}} )
	{

#		if ($self->{CAL}->{$activityid}->{'Checkin (UTC)'}) # make checkin entry optional
		if ($self->{CAL}->{$activityid}->{'Checkin (UTC)'}  && $para->{checkin})	
			{
			# Need a checkin event first
			print MYFILE "BEGIN:VEVENT\r\n";
			print MYFILE "DTSTART:"
			  . $self->dateTimeReWrite(
				$self->{CAL}->{$activityid}->{'Checkin (UTC)'} )
			  . "\r\n";
			print MYFILE "DTEND:"
			  . $self->dateTimeReWrite( $self->{CAL}->{$activityid}->{'Start (UTC)'} )
			  . "\r\n";
			print MYFILE "UID:saneRoster-" . $activityid .'-'.$self->mynow(). "-ci\r\n";
			print MYFILE "DTSTAMP:" . $self->mynow . "\r\n";
			print MYFILE "SUMMARY: Checkin\r\n";
			print MYFILE "DESCRIPTION: Checkin\r\n";
			print MYFILE "END:VEVENT\r\n";
			}

		#print an ICS event
		print MYFILE "BEGIN:VEVENT\r\n";
		# If thsi is an activity code that needs its time correcting
		if ($self->{'patchedTimes'}->{$self->{CAL}->{$activityid}->{CODE}})
			{
			print MYFILE "DTSTART:"
			  . $self->dateTimeReWriteLocal(
				$self->{CAL}->{$activityid}->{'Start (UTC)'} )
		  	. "\r\n";
			print MYFILE "DTEND:"
			  . $self->dateTimeReWriteLocal( $self->{CAL}->{$activityid}->{'End (UTC)'} )
			  . "\r\n"; 
			}
		 else
		 {
			print MYFILE "DTSTART:"
			  . $self->dateTimeReWrite(
				$self->{CAL}->{$activityid}->{'Start (UTC)'} )
		  	. "\r\n";
			print MYFILE "DTEND:"
			  . $self->dateTimeReWrite( $self->{CAL}->{$activityid}->{'End (UTC)'} )
			  . "\r\n"; 
		 	
		 }
		#print MYFILE "UID:saneRoster-" . $activityid .'-'.$self->mynow(). "\r\n";
		print MYFILE "UID:saneRoster-" . $activityid .'-'. $self->dateTimeReWrite($self->{CAL}->{$activityid}->{'Start (UTC)'}).'-'.$self->mynow(). "\r\n";
		print MYFILE "DTSTAMP:" . $self->mynow . "\r\n";
		
		
		print MYFILE "SUMMARY:";

		if($self->{'specialDuties'}->{ $self->{CAL}->{$activityid}->{CODE} })
			{
			foreach my $item (@{$para->{altsummary}})
				{
				if ($self->{CAL}->{$activityid}->{$item})
					{
					print MYFILE $self->{CAL}->{$activityid}->{$item};
					}		
				else
					{
					print MYFILE $item;
					}			
				}
			} 	
		else
			{
			foreach my $item (@{$para->{summary}})
				{ 
				if ($self->{CAL}->{$activityid}->{$item})
					{
					print MYFILE $self->{CAL}->{$activityid}->{$item};
					}					
				else
					{
					print MYFILE $item;
					}			
				}
			}

		if ($self->{CAL}->{$activityid}->{'Roster Notes'})
			{
			print MYFILE ' Notes '.$self->{CAL}->{$activityid}->{'Roster Notes'};
			}
		
		print MYFILE " \r\n";
				
		print MYFILE "DESCRIPTION: ";
		print MYFILE $self->{'specialDuties'}->{ $self->{CAL}->{$activityid}->{CODE} }." "
			if ( $self->{'specialDuties'}->{ $self->{CAL}->{$activityid}->{CODE} } );
		print MYFILE " Depart " . $self->{CAL}->{$activityid}->{'DEP'} . " "
		  if ( $self->{CAL}->{$activityid}->{'DEP'} );
		print MYFILE " Arrive " . $self->{CAL}->{$activityid}->{'ARR'} . " "
		  if ( $self->{CAL}->{$activityid}->{'ARR'} );
		if ( $self->{CAL}->{$activityid}->{'Crew on board'} )
			{
			my $c = $self->{CAL}->{$activityid}->{'Crew on board'};
			$c =~ s/(\d+)/\($1\)	/g;
			print MYFILE "  Crew " .$c. " "	
			}  
		
		  
		print MYFILE "\r\n";
		print MYFILE "END:VEVENT\r\n";
	}

	print MYFILE "END:VCALENDAR\r\n";
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

sub nextMonthKludge()
{
	#makes the kludgy mm_yyyy month identifier that raido uses for the even kludgier date reload function

	my $self = shift;
	my $d    = now;
	my @date = unpack( "A4xA2xA2xA2xA2xA2", $d );

	my $m = $date[1] - 1;
	
	return $m.'_'.$date[0];
}

sub padDate
{
	my $str = shift;

	if ( length($str) == 1 )
	{
		return '0' . $str;
	}
	else
	{
		return $str;
	}
}


	
	
1;
