#!/usr/bin/perl
package Kyloe::Raido::Connector::Logbook;
use Dancer ':syntax';
use CGI;
use WWW::Mechanize;
use HTML::TreeBuilder; 
use HTTP::Cookies;
use Data::Dumper;
use Class::Date qw(:errors date localdate gmdate now -DateParse -EnvC);
use JSON qw(!from_json !to_json);  
use DBI;

use DateTime; 
use DateTime::Event::Sunrise;
use DateTime::Format::ISO8601; 


use strict;
use warnings;


my $specialDuties = {'DO'=>'Day Off','RDO'=>'Rest Day','LVE'=>'Leave','RST'=>'Rest Day','N/A'=>'Not Available'};

#-------------------------------------------------------------------------------------
# Creates a new connector
#-------------------------------------------------------------------------------------



sub new
{
	my $class    = shift;    # Determine the class for the oject to create

	my $obj = {
	};                       # Instantiate a generic empty object

	bless $obj, $class; # 'bless' this new generic object into the desired class
		 
	$obj->{MECH} = WWW::Mechanize->new();    # The robot
	
	$obj->{MECH}->cookie_jar( HTTP::Cookies->new( file => "/home/ian/cookies.txt") );
	
	return $obj;    # Return our newly blessed and loaded object
}

sub login
{
	#A comment
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
	#Now work out if we logged on ok
	 	  
	if ($self->{MECH}->uri() =~ /MainPage.aspx/)
		{
			return 1;
		}
	else
		{
			return 0;
		}
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

		if ($specialDuties->{$item[1]->as_text()})
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
			 #print 'Adding '. $_->{activitydetailid}.' : '. $item[$i]->as_text .' = '.$item[ $i + 1 ]->as_text."\n";
		}
	}

	return 1;
}

sub dateReWrite
{

	# translate DD MONTHNAME YYYY
	# to
	# YYYYMMDD
	my $self       = shift;
	my $dateString = shift;

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

	my @date = split( / /, $dateString );
	return $date[2] . $monthNumbers{ $date[1] } . padDate( $date[0] );
}

#-----------------------------------------------------------------------------------
# Convert text time format HHMM or HMM or HH:MM to a decimal number of hours 
#-----------------------------------------------------------------------------------

sub textTimetoDecimal
	{
	
	my $time = shift;

	# Lets check this data - RM is well flaky
	
	$time = "0000" if (length($time) < 3); 
	$time = '0'.$time if (length($time) == 3);
	
	
	my $minutes = substr($time,-2);
	my $hours = substr($time,0,2);
	
	# my $dec = ($hours+$minutes/60)/24; # as a fraction of a day 
	my $dec = ($hours+$minutes/60); # as a fraction of an hour 

	return $dec;
	}


sub dateTimeReWrite
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
	  . $date[4] . "00Z";
}

sub writeICS  
{
	$| = 1;

	my $self = shift;
	my $para = shift;
	
#	my $file = '/var/services/web/dance/public/cal/'.$para->{staffid}.'.ics';
	my $file = '/var/www/saneRoster/public/cal/'.$para->{staffid}.'.ics';
		
	if (!open (MYFILE, '>'.$file))
	{
		*MYFILE = *STDOUT;
	}
	
	print MYFILE "BEGIN:VCALENDAR\nVERSION:2.0\nMETHOD:PUBLISH\nCOMMENT: Generated by saneRoster \n";


	foreach my $activityid ( keys %{$self->{CAL}} )
	{

#		if ($self->{CAL}->{$activityid}->{'Checkin (UTC)'}) # make checkin entry optional
		if ($self->{CAL}->{$activityid}->{'Checkin (UTC)'}  && $para->{checkin})	
			{
			# Need a checkin event first
			print MYFILE "BEGIN:VEVENT\n";
			print MYFILE "DTSTART:"
			  . $self->dateTimeReWrite(
				$self->{CAL}->{$activityid}->{'Checkin (UTC)'} )
			  . "\n";
			print MYFILE "DTEND:"
			  . $self->dateTimeReWrite( $self->{CAL}->{$activityid}->{'Start (UTC)'} )
			  . "\n";
			print MYFILE "UID:saneRoster-" . $activityid .'-'.$self->mynow(). "-ci\n";
			print MYFILE "DTSTAMP:" . $self->mynow . "\n";
			print MYFILE "SUMMARY: Checkin\n";
			print MYFILE "DESCRIPTION: Checkin\n";
			print MYFILE "END:VEVENT\n";
			}

		#print an ICS event
		print MYFILE "BEGIN:VEVENT\n";
		print MYFILE "DTSTART:"
		  . $self->dateTimeReWrite(
			$self->{CAL}->{$activityid}->{'Start (UTC)'} )
		  . "\n";
		print MYFILE "DTEND:"
		  . $self->dateTimeReWrite( $self->{CAL}->{$activityid}->{'End (UTC)'} )
		  . "\n"; 
		print MYFILE "UID:saneRoster-" . $activityid .'-'.$self->mynow(). "\n";
		print MYFILE "DTSTAMP:" . $self->mynow . "\n";
		
		
		print MYFILE "SUMMARY:";
		
		# print Dumper($para->{summary});
		
		foreach my $item (@{$para->{summary}})
			{
			# print Dumper($item);
			if ($self->{CAL}->{$activityid}->{$item})
				{
				print MYFILE $self->{CAL}->{$activityid}->{$item} . " "
				}
			else
				{
				if(!$specialDuties->{ $self->{CAL}->{$activityid}->{CODE} })
					{
					print MYFILE $item . " ";
					} 
				}
			}
				
		print MYFILE " \n";
				
		print MYFILE "DESCRIPTION:";
		print MYFILE " Depart: " . $self->{CAL}->{$activityid}->{'DEP'} . " "
		  if ( $self->{CAL}->{$activityid}->{'DEP'} );
		print MYFILE " Arrive: " . $self->{CAL}->{$activityid}->{'ARR'} . " "
		  if ( $self->{CAL}->{$activityid}->{'ARR'} );
		if ( $self->{CAL}->{$activityid}->{'Crew on board'} )
			{
			my $c = $self->{CAL}->{$activityid}->{'Crew on board'};
			$c =~ s/(\d+)/\  $1/g;
			print MYFILE "  Crew: " .$c  . " "	
			}  
		
		  
		print MYFILE "\n";
		print MYFILE "END:VEVENT\n";
	}

	print MYFILE "END:VCALENDAR\n";
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

#
# Log book scraping code
#


sub getRaidoData
	{
	my $self = shift;

	my $startDate = shift; # dates are text strings in format DD/MM/YYYY
	my $endDate = shift; # dates are text strings in format DD/MM/YYYY
	my $staff_id = shift;
	my $dbh = shift;

	
	$self->getIndexPage($startDate,$endDate);
	$self->getVoyageIDs();
	$self->insertDataFromHash($staff_id, $dbh);
		
	}

#--------------------------------------------------------------------------------------
# Retrieve the page with the list of all voyages
#--------------------------------------------------------------------------------------

sub getIndexPage
{
	my $self = shift;
	my $startDate = shift;  # all dates are text strings in format DD/MM/YYYY
	my $endDate = shift;    # all dates are text strings in format DD/MM/YYYY
	
#	$self->{MECH}->get($self->{'config'}->{'performed'}->{'allVRurl'}) or die "Could not retrieve voyage report index page";
	$self->{MECH}->get("https://raido.loganair.co.uk/raido/Dialogues/HumanResources/HumanResourceMyVoyageReporting.aspx") or die "Could not retrieve voyage report index page";


	$self->{MECH}->form_name("form1");
	$self->{MECH}->field( 'ctl00$CPHcontent$actid','');
	$self->{MECH}->field( 'ctl00$CPHcontent$hidActivityIdsToUpdate', '' );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$dpValidFrom', dateToDDMMMYY($startDate) );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$dpValidTo', dateToDDMMMYY($endDate) );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$fAction', '' );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfCalorder','');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfMonthShortNames','JAN,FEB,MAR,APR,MAY,JUN,JUL,AUG,SEP,OCT,NOV,DEC');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfNewParameter','');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfReadonly','');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfValidFrom',dateToYYYYMMDD($startDate));
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfValidTo',dateToYYYYMMDD($endDate));
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfWdMinNames','Su,Mo,Tu,We,Th,Fr,Sa');
	$self->{MECH}->field( 'ctl00$fAction','');
	$self->{MECH}->submit_form(form_name => 'form1');


	
	return 1;
}

#--------------------------------------------------------------------------------------
# get detailed voyage report for a VR id
#--------------------------------------------------------------------------------------


sub getVoyageIDs()
	{
	my $self = shift;
#	my $dbh = shift;

	$self->parseResponseToTree();

	my $p = sub 
		{
		my $t = shift;
		my $a = shift;
		substr($a,index($a,'(')+1,6);
		};

	my $q = sub 
		{
		my $t = shift;
		my $a = shift;
		substr($t,0,7);
		};

	my $r = sub 
		{
		my $t = shift;
		my $a = shift;
		
		$t =~ s/,/ /g;
		
		return $t;
		};

	my $table_data = parseTable
		(
		TREE => $self->{TREE}, 
		TABLE_IDENTIFIER => ['_tag','table','id','CPHcontent_fGrid'], 
		HEADER_ROW_IDENTIFIER => ['_tag', 'tr',],
		HEADER_ITEM_IDENTIFIER => ['_tag', 'th'],
		DATA_ROW_IDENTIFIER => ['_tag', 'tr'],		
		DATA_ITEM_IDENTIFIER => ['_tag', 'td'],
		PARSER => {0=>{VRID=>$p},1=>{TEXT=>$q},8=>{TEXT=>$r}}
		);
	
	#debug Dumper($table_data);
	
	my $rowCount = 0;
	
	# Extract all data from index page - and store in memory structures so that we can re-use MECH to get detail pages
	
	for my $r (@{$table_data})
		{
			
		if ($rowCount > 1)
			{

			$self->{ROWS}->{$r->[0]->{'VRID'}}->{'comments'} =  		$r->[0]->{'TEXT'};
			$self->{ROWS}->{$r->[0]->{'VRID'}}->{'sector_date'} =  		$r->[1]->{'TEXT'};
			$self->{ROWS}->{$r->[0]->{'VRID'}}->{'dep_time'} =  		$r->[2]->{'TEXT'};
			$self->{ROWS}->{$r->[0]->{'VRID'}}->{'arr_time'} =  		$r->[5]->{'TEXT'};
			$self->{ROWS}->{$r->[0]->{'VRID'}}->{'landing_pilot_name'}= $r->[8]->{'TEXT'};
			$self->{ROWS}->{$r->[0]->{'VRID'}}->{'external_sector_id'}= $r->[0]->{'VRID'};
			$self->{ROWS}->{$r->[0]->{'VRID'}}->{'sector_sequence'} = 	$rowCount;
										
			}
		$rowCount++;
		}
		
	# Now for each entry in the row table get the detail page and flesh out the data
	# for each VRID
	# If we dont already have detail (test sector date)
	# retrieve the detail page
	# 	get list of VRIDs held on this page in order
	#   for each VrID
	#     get from, to , CAP, FO, CC, landing pilot, aircraft
	
	for my $vrid (keys $self->{ROWS})
		{
		next if ($self->{ROWS}->{$vrid}->{'dep'}) ; # We have already go this one


		$self->{MECH}->field( 'actid',$vrid);
		$self->{MECH}->field( 'ctl00$CPHcontent$actid',$vrid);
		$self->{MECH}->submit_form(form_name => 'form1');
		
		$self->parseResponseToTree();
		
		my @v = $self->{TREE}->look_down('_tag','input','class','hidLegId');
		
		my @vrid;
		
		foreach my $tag (@v)
			{
			push(@vrid,$tag->attr('value'));
			}
		
		# we now have a list of VRIDs on this page
		
		# Get crew details
		
		my @ranks = $self->{TREE}->look_down('_tag','span','class','labRank');
		my @crews = $self->{TREE}->look_down('_tag','span','class','labCrewName'); 

		my $crew;
		my $crewComment = 'Crew: ';
	

		for (my $x=0;$x < $#ranks+1; $x++)
			{
			$crew->{$ranks[$x]->as_text()} = $crews[$x]->as_text();
			$crew->{$ranks[$x]->as_text()} =~ s/,/ /g; # Replace comma with white space to match old rainmaker format
			$crewComment .= $ranks[$x]->as_text().': '.$crews[$x]->as_text().' ';	 
			}
			
		# crew details	
		
		my $message = 	$self->{TREE}->look_down('_tag','div','style','width: 98%; margin: 5px;');
	#debug Dumper($message->as_text());

		my @summ = $self->{TREE}->look_down('_tag','span','id',qr/CPHcontent_rptTimes_labFlightInfo_\d/);
		
		my $c = 0;

		foreach my $s (@summ)
			{
			my @fields = split(/ /,$s->as_text());
			$self->{ROWS}->{$vrid[$c]}->{'dep'} = $fields[3];
			$self->{ROWS}->{$vrid[$c]}->{'arr'} = $fields[4];
			$self->{ROWS}->{$vrid[$c]}->{'reg'} = $fields[5];
			$self->{ROWS}->{$vrid[$c]}->{'CAP'} = $crew->{'CAP'};
			$self->{ROWS}->{$vrid[$c]}->{'FO'}  = $crew->{'FO'};
			$self->{ROWS}->{$vrid[$c]}->{'CA'}  = $crew->{'CA'};
			$self->{ROWS}->{$vrid[$c]}->{'long text'} = $s->as_text();
			# $self->{ROWS}->{$vrid[$c]}->{'comments'} .= $crewComment; # crew compliment included in summary in Raido
			
			$c++; 
			}

		# attach messages to ops (comments) to first sector of day
		
		$self->{ROWS}->{$vrid[0]}->{'comments'} .= $message->as_text();
		
		# airborne times
		
		@summ = $self->{TREE}->look_down('_tag','span','id',qr/CPHcontent_rptTimes_ActualTakeOff_\d/);
		
		$c = 0;
		
		foreach my $s (@summ)
			{
			$self->{ROWS}->{$vrid[$c]}->{'airborne_time'} = $s->as_text();
			$c++; 
			}

		# landing times
		
		@summ = $self->{TREE}->look_down('_tag','span','id',qr/CPHcontent_rptTimes_ActualTouchDOwn_\d/); # Capitalisation Typo is intentional [sic]
		
		$c = 0;
		
		foreach my $s (@summ)
			{
			$self->{ROWS}->{$vrid[$c]}->{'land_time'} = $s->as_text();
			$c++; 
			}
		
		
		}
	}
	
#------------------------------------------------------------------------------------- 
# returns the voyage reprort rows as an html table
#-------------------------------------------------------------------------------------

sub dataAsHTML()
	{
	my $self = shift;
	my $str;

	$str.='<table>';
	
	for my $r (keys $self->{ROWS})
		{
		$str.='<tr>';
		
		foreach my $f (keys %{$self->{ROWS}->{$r}})
			{
			$str.='<td>'.$f.'</td><td>'.$self->{ROWS}->{$r}->{$f}.'</td>' if ($self->{ROWS}->{$r}->{$f});
			}
		$str.='</tr>';
		}
	$str.='</table>';
	
	return $str;

	}	
	
#------------------------------------------------------------------------------------- 
# takes an hash or rows of data, each row is a hash of fields - inserts each row in turn
# where a lookup table is referenced, an entry is 'lookup'ed or created
#-------------------------------------------------------------------------------------

sub insertDataFromHash
	{
	my $self = shift;
	my $staff_id = shift;
	my $dbh = shift;

	for my $r (keys $self->{ROWS})
		{
		my %row = 	(
  					'sector_date'			=>	$self->{ROWS}->{$r}->{'sector_date'},
  					'sector_seq'			=>	$self->{ROWS}->{$r}->{'sector_sequence'},
  					'dep'					=>	$self->{ROWS}->{$r}->{'dep'},
  					'arr'					=>	$self->{ROWS}->{$r}->{'arr'},
  					'dep_time'				=>	textTimetoText($self->{ROWS}->{$r}->{'dep_time'}),
  					'airborne_time'			=>	textTimetoText($self->{ROWS}->{$r}->{'airborne_time'}),
  					'land_time'				=>	textTimetoText($self->{ROWS}->{$r}->{'land_time'}),
  					'arr_time'				=>	textTimetoText($self->{ROWS}->{$r}->{'arr_time'}),
  					'external_sector_id'	=>	$self->{ROWS}->{$r}->{'external_sector_id'},
	  				'p1_name'				=>	trim($self->{ROWS}->{$r}->{'CAP'}),
	  				'p2_name'				=>	trim($self->{ROWS}->{$r}->{'FO'}),
  					'landing_pilot_name'	=>	trim($self->{ROWS}->{$r}->{'landing_pilot_name'}),
  					'cc_name'				=>	trim($self->{ROWS}->{$r}->{'CA'}),
  					'aircraft_registration'	=>	$self->{ROWS}->{$r}->{'reg'},
  					'comments'				=>	$self->{ROWS}->{$r}->{'comments'},
  					'logbook_id'			=>	$staff_id,
  					'external_system_name'	=>	'raido',					
					);

		
		$self->insertRow(\%row,$staff_id, $dbh);
		
#		foreach my $f (keys %{$self->{ROWS}->{$r}})
#			{
#			# $str.='<td>'.$f.'</td><td>'.$self->{ROWS}->{$r}->{$f}.'</td>' if ($self->{ROWS}->{$r}->{$f});
#			}
		}
	}		
	
sub insertRow
	{
	my $self = shift;
	my $rowRef = shift;
	my $staff_id = shift;
	my $dbh = shift;
	
	# determine each of the lookup id values first
	# they are
	# P1, P2, CC, Landing Pilot based on Name, Aicraft ID based on Reg, logbook owner based on staff_id
	
	my $p1_id 				= register($dbh,'person','name',$rowRef->{'p1_name'});
	my $p2_id 				= register($dbh,'person','name',$rowRef->{'p2_name'});
	my $cc_id 				= register($dbh,'person','name',$rowRef->{'cc_name'});
	my $landing_pilot_id 	= register($dbh,'person','name',$rowRef->{'landing_pilot_name'});
	my $aircraft_id 		= register($dbh,'aircraft','aircraft_reg',$rowRef->{'aircraft_registration'});
	my $logbook_id 			= register($dbh,'person','staff_id',$staff_id);

	# where possible pre calculate hours and landings
	
	# Block hours - arr_time as dec - dep_time 
	
	my $hrs_block = textTimetoDecimal($rowRef->{'arr_time'}) - textTimetoDecimal($rowRef->{'dep_time'});
	$hrs_block = 24+$hrs_block if ($hrs_block < 0); # landed after midnight

	# work out if the landing belongs the log book owner
	

	# and caclulate night hours and landings

	my $sector_date = $rowRef->{'sector_date'};

	my ($hrs_night,$l) = getNightHours(getSectorDateTimes(dateToYYYYMMDD($rowRef->{'sector_date'}),$rowRef->{'dep_time'},$rowRef->{'arr_time'}),getSunriseSunset(dateToYYYYMMDD($rowRef->{'sector_date'})));


	my $land_day	=	0;
	my $land_night	=	0;
	
	if ($logbook_id == $landing_pilot_id)
		{
		if ($l)
			{
			$land_night = 1;
			}
		else
			{
			$land_day = 1;
			}
		}	

	$hrs_night  = 0 if (!defined($hrs_night));
	
	SQLinsert
		($dbh,'sector',
			{
			'sector_date' 		=> $rowRef->{'sector_date'},
			'external_sector_id'=> $rowRef->{'external_sector_id'},
			'sector_seq' 		=> $rowRef->{'sector_seq'},
			'dep' 				=> $rowRef->{'dep'},
			'arr'		 		=> $rowRef->{'arr'},
			'dep_time' 			=> $rowRef->{'dep_time'},
			'airborne_time'		=> $rowRef->{'airborne_time'},
			'land_time' 		=> $rowRef->{'land_time'},
			'arr_time' 			=> $rowRef->{'arr_time'},
			'hrs_block'       	=> $hrs_block,
			'hrs_ifr'       	=> $hrs_block,
			'hrs_if'       		=> $hrs_block,
			'hrs_pic'       	=> $hrs_block,
			'hrs_tot'       	=> $hrs_block,
			'hrs_night'			=> $hrs_night,
			'land_day'			=> $land_day,
			'land_night'		=> $land_night,
			'p1_id'				=> $p1_id,
			'p2_id'				=> $p2_id,
			'cc_id'				=> $cc_id,
			'landing_pilot_id'	=> $landing_pilot_id,
			'aircraft_id'		=> $aircraft_id,
			'logbook_id'		=> $logbook_id,
			'external_system_name'	
								=> $rowRef->{'external_system_name'},
			'comments'			=> $rowRef->{'comments'}
			}
		);

	
	}
	
#-------------------------------------------------------------------------------------
# Register  - gets ID for item from lookup table - if not found - inserts and gets ID
#-------------------------------------------------------------------------------------

sub register
	{
	my $dbh = shift;
	my $table = shift;
	my $field = shift;
	my $val = shift;

	
	# Try and select thing from table
	# if found - return ID
	# else insert, then select and return ID
	
	my $id = getID($dbh,$table,$field,$val);
	
	return $id if ($id);
	
	SQLinsert($dbh,$table,{$field=>$val});

	return getID($dbh,$table,$field,$val);
	}
	
#-------------------------------------------------------------------------------------
# Insert
#-------------------------------------------------------------------------------------

sub SQLinsert
	{
	my $dbh = shift;
	my $table = shift;
	my $params = shift;
	
	my $comma = '';
	my $fields = '';
	my $values = '';
	
	foreach my $key (keys %$params)
		{
		$fields .= $comma.$key;
		$values .= $comma.'\''.sqlQuoteSafe($params->{$key}).'\'';
		$comma = ',';
		}
		
	my $statement = "insert into $table ($fields) values ($values)";

	my $rows = $dbh->do($statement) or die "Tried to $statement resulting in: ".$dbh->errstr;

	return $rows;
	}
	
	
#-------------------------------------------------------------------------------------
# Update
#-------------------------------------------------------------------------------------

sub SQLupdate
	{
	my $dbh = shift;
	my $table = shift;
	my $conditions = shift;
	my $params = shift;
	my $NQ = shift;
	
	my $comma = '';
	my $assignments = '';
	
	
	foreach my $key (keys %$params)
		{
		if ($NQ)
			{
			$assignments .= $comma.$key.'='.$params->{$key};
			}
		else
			{
			$assignments .= $comma.$key.'=\''.sqlQuoteSafe($params->{$key}).'\'';
			}
		$comma = ',';
		}
	my $statement = "update $table set $assignments where $conditions";
	my $rows = $dbh->do($statement) or die "Tried to $statement resulting in :".$dbh->errstr;
	return $rows;
	}
	
#-------------------------------------------------------------------------------------
# getID  - gets ID for item from lookup table 
#-------------------------------------------------------------------------------------
	
sub getID
	{
	
	my $dbh = shift;
	my $table = shift;
	my $field = shift;
	my $val = shift;
	
	
	my $statement = "select ID from $table where $field = \'".sqlQuoteSafe($val)."\'";	

	my @id = $dbh->selectrow_array($statement);
	
	return $id[0];
	
	}

#-----------------------------------------------------------------------------------
# Display a decimal number of hours in format (H)HMM as a time HH:MM, padded and colon'd
#-----------------------------------------------------------------------------------

sub textTimetoText
	{
	my $time = shift;
	
	$time = "0000" if (!$time); # more kludge catching
	$time =~ s/^\s+|\s+$//g;    # more kludge catching
	
	# Added to cover duff data in RainMaker & Raido
	
	$time = "0000" if (length($time) < 3);
	
	my $minutes = substr($time,-2);
	my $hours = substr($time,0,length($time)-2);
	
	$hours = '0'.$hours if (length($hours) == 1);
	
	return $hours.':'.$minutes; 
	}	
	
#-------------------------------------------------------------------------------------
# ltrim and rtrim all data elements in a hash 
#-------------------------------------------------------------------------------------
	
sub hashTrim
	{
	my $hashRef = shift;
	foreach my $key (keys $hashRef)
		{
		$hashRef->{$key} =~ s/^\s+|\s+$//g;
		}
	}

#-------------------------------------------------------------------------------------
# trim both ends 
#-------------------------------------------------------------------------------------

sub trim($)
{
	my $string = shift;
	$string = "" unless ($string);
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	
	return $string;
}

#-------------------------------------------------------------------------------------
# Translates any stray ' into \' 
#-------------------------------------------------------------------------------------


sub sqlQuoteSafe
	{
	my $str = shift;
	$str = "" if (!defined($str));
	$str =~ s/\'/\'\'/g;
	return $str;
	}
#------------------------------------------------------------------------------------- 
# Takes the in memory response and parses it into a tree
#-------------------------------------------------------------------------------------

sub parseResponseToTree
	{
	my $self = shift;

	if ($self->{MECH}->response()->is_success())
		{
		$self->{TREE} = HTML::TreeBuilder->new();
		$self->{TREE}->parse($self->{MECH}->content());
				
		$self->{TREE}->elementify();
		#print "Elementified\n";
		}
	else 	
		{
		die "Did not retrieve page\n";
		}
	}


#-------------------------------------------------------------------------------------
# parseTable - takes a table element 
# reads headers from nominated row
# reads data starting from nominated row - till named end or just till end of table
# stashes data in an array of arrays, one per row, named as per 
#-------------------------------------------------------------------------------------

sub parseTable()
	{
	my %args = ( 
	TREE => '',
	TABLE_IDENTIFIER => '',
	HEADER_ROW_IDENTIFIER => '',
	HEADER_ITEM_IDENTIFIER => '',
	DATA_ROW_IDENTIFIER => '',
	DATA_ITEM_IDENTIFIER => '',
	PARSER => {},
	INDEX => 0, # nth occurence of this table base 0
	@_,         # argument pair list goes here
	);

	# validate essential parameters

	if ($args{TABLE_IDENTIFIER} eq '')
		{
		warn 'Table must be named in TABLE_IDENTIFIER ,TABLE_IDENTIFIER_VALUE parameters\n';
		return 0;
		}

	# find table
	
		print Dumper($args{TREE});
	
	my @table_arr = $args{TREE}->look_down('_tag','table',@{$args{TABLE_IDENTIFIER}});
	

	
	my $table = $table_arr[$args{INDEX}];
	
	# find header row
	
	my $header = $table->look_down(@{$args{HEADER_ROW_IDENTIFIER}});
	
	# if found start parsing it
	
	my @header_items = $header->look_down(@{$args{HEADER_ITEM_IDENTIFIER}});
	
	my @labels;
	
	foreach my $header_label (@header_items)
		{
#		print "LABEL TEXT ".$header_label->as_text()."\n";
		push @labels,{TEXT=>$header_label->as_text(),A=>''};
		}
 	
 	my $x=0;	

	my $row_array->[$x++] = \@labels;
		
	# Now get a list of data rows and for each row add a hash to an array of hashes
	
	my @rows = $table->look_down(@{$args{DATA_ROW_IDENTIFIER}});
	
#	print "Found ".$#rows." data rows\n";
	
	# stash rows one at a time
	 	
 	foreach my $row (@rows)
		{
		my @data_items = $row->look_down(@{$args{DATA_ITEM_IDENTIFIER}});
		
		# print "Found ".$#data_items." data items\n";
		
		my @row;
		my $col_index = 0;
		foreach my $data_item (@data_items) 
			{ 
			my @hrefs = $data_item->look_down('_tag','a');
			my $text;
			my $a;
			my $parsedVals;
			
			if (@hrefs)
				{
				$text=$data_item->as_text();
				$a = $hrefs[0]->attr('href');
				}
			else
				{
				$text=$data_item->as_text();
				$a = '';				
				}  
			
			
			$parsedVals = {TEXT=>$text,A=>$a};
			
			# Now, if there is a parser for this cell - run it to process the contents (will overwrite TEXT if that is one of the parser pabels)
			
			if ($args{PARSER}{$col_index})
				{
				foreach my $key (keys %{$args{PARSER}{$col_index}})
					{
#					print "Key is ".$key." col is ".$col_index."\n";
					$parsedVals->{$key} = $args{PARSER}{$col_index}->{$key}->($text,$a);
					}
				}

#			if ($parsedVals->{VRID})
#			{
#			print "a text=$text href=$a vrid=".$parsedVals->{VRID}."\n";	
#			}
#			else
#			{
#				print "a text=$text href=$a\n";
#			}
			


			push @row, $parsedVals;
			
			$col_index++;
			}
		$row_array->[$x++] =\@row;
		}
			
	return $row_array;
	
	}

#
# Utilities
#

#-----------------------------------------------------------------------------------
# Convert DD/MM/YYYY to DDMMMYY 
#-----------------------------------------------------------------------------------

sub dateToDDMMMYY
	{
	my $date = shift;
	my @date_arr = split('/',$date);
	return $date_arr[0].monthNum($date_arr[1]).substr($date_arr[2],-2);
	}


#-----------------------------------------------------------------------------------
# Convert DD/MM/YYYY or DDMMMYY to YYYYMMDD
#-----------------------------------------------------------------------------------

sub dateToYYYYMMDD
	{
	my $date = shift;
	
	if ($date =~ /\d\d\/\d\d\/\d\d\d\d/)
		{
		my @date_arr = split('/',$date);
		return $date_arr[2].$date_arr[1].$date_arr[0];
		}
	elsif ($date =~ /\d\d\w\w\w\d\d/)
		{
		my @date = unpack( "A2A3A2", $date);
		my $months = {'JAN'=>'01','FEB'=>'02','MAR'=>'03','APR'=>'04','MAY'=>'05','JUN'=>'06','JUL'=>'07','AUG'=>'08','SEP'=>'09','OCT'=>'10','NOV'=>'11','DEC'=>'12'};
		return '20'.$date[2].'-'.$months->{$date[1]}.'-'.$date[0];
		}
	else
		{
		die "Could not convert date	$date";
		}
	}


#-----------------------------------------------------------------------------------
# Convert month to number and back 
#-----------------------------------------------------------------------------------

sub monthNum($)
	{
	my $m = shift;
	my $mnum = {
		'JAN'=>1,'FEB'=>2,'MAR'=>3,'APR'=>4,'MAY'=>5,'JUN'=>6,'JUL'=>7,'AUG'=>8,'SEP'=>9,'OCT'=>10,'NOV'=>11,'DEC'=>12,
		1=>'JAN',2=>'FEB',3=>'MAR',4=>'APR',5=>'MAY',6=>'JUN',7=>'JUL',8=>'AUG',9=>'SEP',10=>'OCT',11=>'NOV',12=>'DEC',
		'01'=>'JAN','02'=>'FEB','03'=>'MAR','04'=>'APR','05'=>'MAY','06'=>'JUN','07'=>'JUL','08'=>'AUG','09'=>'SEP','10'=>'OCT','11'=>'NOV','12'=>'DEC'
	};

	return $mnum->{$m};
	}


#-----------------------------------------------------------------------------------
# Work out sunrise and sunset times for this sector as DateTime format
#-----------------------------------------------------------------------------------
 
 
sub getSunriseSunset($)
	{
	my $shift_date = shift; # date string in ISO format
	
	my $shift_dt = DateTime::Format::ISO8601->parse_datetime( $shift_date."T00:00:01" );

	my $long = '-4.5';
	my $lat = '55';
	my $alt = '-0.833';
	my $iter = '1';
	


	my $rise_ev = DateTime::Event::Sunrise ->sunrise (
                        longitude =>'-4.5',
                        latitude =>'55',
                        altitude => '-0.833',
                        iteration => '1'
                  );

	my $set_ev = DateTime::Event::Sunrise ->sunset (
                        longitude =>'-4.5',
                        latitude =>'55',
                        altitude => '-0.833',
                        iteration => '1'
                  );

	my $rise_dt = $rise_ev->next( $shift_dt ); 
	my $set_dt = $set_ev->next( $shift_dt ); 



	return ($rise_dt,$set_dt);
	}


#-----------------------------------------------------------------------------------
# Calculate number of night hours as a decimal - and the number (1 or 0) of night landings
#-----------------------------------------------------------------------------------
 
 
sub getNightHours()
	{
	my $dep = shift;
	my $arr = shift;
	my $rise = shift;
	my $set = shift;
	
	setLocale($rise);
	setLocale($set);
	setLocale($dep);
	setLocale($arr);
	
	# Cases are
	# Arr before rise, dep after set = all night
	# Arr after rise dep before set = no night
	# Otherwise = if_positive(rise-dep) + if_positive(arr-set)
	
	my $duration;
	my $hours;
	my $minutes;
	
	# Case 1 land before sunrise or depart after sunset
		
	if ((DateTime->compare($rise,$arr) == 1) || (DateTime->compare($dep,$set) == 1))
		{
		# print "Case 1\n";
		# Its all in the dark
		$duration = $arr->subtract_datetime($dep);
		($hours,$minutes) = $duration->in_units('hours','minutes');
		return ($hours+$minutes/60,1); # 1 = 1 night landing
		}
	
	# Case 2 dep in day land in day
	
	if ((DateTime->compare($dep,$rise) == 1) && (DateTime->compare($set,$arr) == 1))
		{
		# print "Case 2\n";
		return (0,0); # all day time - day landing
		}
		
	# Case 3 flight crosses sunrise, sunset, or both
	
	if ((DateTime->compare($rise,$dep) == 1) || (DateTime->compare($arr,$set) == 1))
		{
		# Its the sum of the two dark bits
		# print "Case 3\n";
		my $totHours;
		my $totMinutes;

		$duration = $rise->subtract_datetime($dep);
		($hours,$minutes) = $duration->in_units('hours','minutes');
		if ($hours < 0 || $minutes < 0)
			{
			$hours = 0;
			$minutes = 0;
			}

		($totHours,$totMinutes) = ($hours,$minutes);
		
		$duration = $arr->subtract_datetime($set);
		($hours,$minutes) = $duration->in_units('hours','minutes');
		if ($hours < 0 || $minutes < 0)
			{
			$hours = 0;
			$minutes = 0;
			}
		
		$totHours += $hours;
		$totMinutes += $minutes;
		
		my $nightLanding = (DateTime->compare($set,$arr) == 1)? 0 : 1;
		return ($totHours+$totMinutes/60,$nightLanding); # all day time - day landing
		}
	
	die "Unexpected case found - shouldn't have got here";
	
	}


#-----------------------------------------------------------------------------------
# Make sure date time is in UK DST
#-----------------------------------------------------------------------------------

sub setLocale($)
	{
	my $date = shift;
	$date->set_time_zone('Europe/London');
	$date->set_locale('en_GB');
	}

#-----------------------------------------------------------------------------------
# Create DateTime objects for the dep and arr on this sector
#-----------------------------------------------------------------------------------

sub getSectorDateTimes()
	{
	my $sector_date = shift;
	my $dep_time = shift;
	my $arr_time = shift;
	
	my $dep_dt = DateTime::Format::ISO8601->parse_datetime( $sector_date."T".$dep_time.":00");
	my $arr_dt = DateTime::Format::ISO8601->parse_datetime( $sector_date."T".$arr_time.":00" );

	
	return ($dep_dt,$arr_dt);
	
	}
#-----------------------------------------------------------------------------------
# convert date in format dd/mm/yyyy to yyyy-mm-dd for database storage
#-----------------------------------------------------------------------------------

sub formatDate
	{
	my $date = shift;
	
	
	
	my @date_arr = split('/',$date);
	return $date_arr[2].'-'.$date_arr[1].'-'.$date_arr[0];
	}

1;

