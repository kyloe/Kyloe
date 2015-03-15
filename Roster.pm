#!/usr/bin/perl
package Roster;


use strict;
use warnings;

use HTML::TreeBuilder;
use Date::Calc qw(:all);  
use WWW::Mechanize;
use Data::Dumper;
# use PDF::Report;
use Config::General; 

use base qw( Exporter );

our @EXPORT = qw( new asHTML parse getMyId parsedOK compare login);

#-------------------------------------------------------------------------------------
# State variables for roster navigation
#-------------------------------------------------------------------------------------

my $currentDayIndex = 0;
my $currentSectorIndex = 0;
my @sortedDays;

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
	
	my $conf = new Config::General('roster.cnf');

	my %hash = $conf->getall();
	$obj->{'config'} = \%hash;

	return $obj;         # Return our newly blessed and loaded object
	}

#-------------------------------------------------------------------------------------
# Logs on and gets the planned roster
#-------------------------------------------------------------------------------------


sub retrievePlannedRoster
	{
	my $self = shift;
	my $mech = WWW::Mechanize->new();		# The robot

	$self->login($mech);
			
	#$mech->get('http://crewweb.loganair.co.uk/CWP_RosterTW.aspx');
	$mech->get($self->{'config'}->{'planned'}->{'url'});
	$self->{'response'} = $mech->response();
		
	$self->logout($mech);

	$self->parsePlannedRoster();

	}

#-------------------------------------------------------------------------------------
# Logs on and gets the executed roster
#-------------------------------------------------------------------------------------


sub retrieveExecutedRoster
	{
	my $self = shift;
	my $start = shift;
	my $end = shift;
	
	my $mech = WWW::Mechanize->new();		# The robot

	$self->login($mech);
		
	my $url = $self->{'config'}->{'performed'}->{'url'};
	$url =~ s/\$start/$start/gi;
	$url =~ s/\$end/$end/gi;
	$self->{'config'}->{'performed'}->{"YEAR"} = substr($start, 0, 4);
		
	print "Fetch: ".$url."\n";


	$mech->get($url);
	
	$self->{'response'} = $mech->response();
		
	$self->logout($mech);

	$self->parseExecutedRoster();

	}


#-------------------------------------------------------------------------------------
# Takes the response and parses it as a planned roster
#-------------------------------------------------------------------------------------

sub parsePlannedRoster()
	{
	my $self = shift;
	$self->parseRoster('planned'); # Need to pass in the name of the table that we are looking for as it changes on various pages
	}

#-------------------------------------------------------------------------------------
# Takes the response and parses it as an 'as performed' roster
#-------------------------------------------------------------------------------------

sub parseExecutedRoster()
	{
	my $self = shift;
	$self->parseRoster('performed'); # Need to pass in the name of the table that we are looking for as it changes on various pages
	}


#-------------------------------------------------------------------------------------
# Generic response parse
#-------------------------------------------------------------------------------------

sub parseRoster()
	{
	my $self = shift;
	my $tableType = shift;
	my $name = 'Un-named';

	my $tableName = $self->{'config'}->{$tableType}->{'table'};

	my $data = [];
	if ($self->{'response'}->is_success)
		{
		my $tree  = HTML::TreeBuilder->new();
		$tree->parse($self->{'response'}->content());
		$tree->elementify();

		my $head = $tree->look_down('_tag','span','id','_header__labLogin');
		$name = $head->content()->[0];

		my $table = $tree->look_down('_tag','table','id',$tableName);

		my @rows = $table->find('tr');
		
		my $days;

		foreach (@rows)
			{
			my @cells = $_->find('td');


			next unless (@cells); 							# Skip empty lines
			next if ($_->look_down('_tag','table','class','TWBorderBottom'));	# Skip Crew On Board entries
			next if ($_->attr('class') =~ /bgDark/);				# Skip Crew On Board entries
			next if ($_->attr('class') =~ /selectRow/i);				# Skip Crew On Board entries
			next if ($_->attr('class') =~ /RosterHeader/i);				# Skip Crew On Board entries

			# $datarow->{'style'} = $_->attr('class');

			my $currentmonth = 'UNSPECIFIED'; # If these values show up in any print out its a bug
			my $currentdate  = 'UNSPECIFIED';
			my $currentyear  = 'UNSPECIFIED';
			my $sector;

			foreach (@cells)
				{
				
				no warnings 'uninitialized';
				if ($_->content() && ($_->attr('class') =~ /^Roster/i))
					{
					my $val = $_->content()->[0];
					my $class = $_->attr('class');
					if ( $class =~ /^RosterRowCheck/) # Parses checkin and checkout times for that days work
						{
						$val =~ /(\d\d)(\w\w\w) (\d\d:\d\d)/;
						#$currentyear = This_Year();
						#$currentyear += 1 if ((Delta_Days(This_Year(),Decode_Month($2),$1,Today()) > 0)  && ($tableType eq 'planned')); # Add one on if this date is in Next year
						#$currentyear -= 1 if ((Delta_Days(This_Year(),Decode_Month($2),$1,Today()) < 0)  && ($tableType eq 'performed')); # Add one on if this date is in Next year
						
						$currentyear = $self->{'config'}->{'performed'}->{"YEAR"};
						
						
						push(@{$days->{$1." ".$2." ".$currentyear}->{$_->attr('class')}},$3);
						$currentdate = $1;
						$currentmonth = $2;
						}
					else # This is a sector item 
						{
						if ($val =~ /(\d\d)(\w\w\w) (\d\d:\d\d)/) # then its a start or end time
							{
							$sector->{$_->attr('class').'Date'} = $1;
							$sector->{$_->attr('class').'Month'} = $2;
							$sector->{$_->attr('class').'Time'} = $3.":00";
							#$sector->{$_->attr('class').'Year'} = This_Year();
							$sector->{$_->attr('class').'Year'} = $self->{'config'}->{'performed'}->{"YEAR"};
							#$sector->{$_->attr('class').'Year'} += 1 if ((Delta_Days(This_Year(),Decode_Month($2),$1,Today()) > 0) && ($tableType eq 'planned')); # Add one on if this date is in Next year
							#$sector->{$_->attr('class').'Year'} -= 1 if ((Delta_Days(This_Year(),Decode_Month($2),$1,Today()) < 0) && ($tableType eq 'performed')); # Add one on if this date is in Next year
							$sector->{$_->attr('class').'FullDate'} = $sector->{$_->attr('class').'Year'}.":".Decode_Month($2).":".$1;
							# Only stash the current stuff - if this is the start time - end time may be tomorrow
							if ($_->attr('class') eq 'RosterRowStart')
								{
								$currentdate = $1;
								$currentmonth = $2;
								$currentyear = $sector->{$_->attr('class').'Year'};
								}			
							}
						else # its just any other data item
							{
							$sector->{$_->attr('class')} = $val;
							}
						
						}						
					}
				} # End for cells
				
				# Check to see if checkin and checkout are set - if not - set some default values (for DO, RDO, LVE etc)
				
				if ($sector->{'RosterRowActivity'} eq 'DO')
					{
					push(@{$days->{$currentdate." ".$currentmonth." ".$currentyear}->{'RosterRowCheckin'}},"09:00:00");
					push(@{$days->{$currentdate." ".$currentmonth." ".$currentyear}->{'RosterRowCheckout'}},"17:00:00");
					}
					
				
				push (@{$days->{$currentdate." ".$currentmonth." ".$currentyear}->{'sectors'}},$sector);
				
			} # End for rows
		
		$self->{'name'} = $name;
		$self->{'roster'} = $days;
		$self->{'status'} = 1;

		$self->patchCheckinDates(); # fixes bug in SR where some days have no checkin date set


		}
	else
		{
		$self->{'status'} = 0;
		}

	return 	$self->{'status'};
	}
	
#-------------------------------------------------------------------------------------
# Fixes a bug in SR where some checkin/checkout times are not displayed
# Assumes report 1 hour, 20 mins post flight
#-------------------------------------------------------------------------------------	

sub patchCheckinDates
	{
	my $self = shift;
	foreach my $day  (keys %{$self->{'roster'}})
		{

		if (!$self->{'roster'}->{$day}->{'RosterRowCheckin'}->[0])
			{
			(my $hours, my $minutes) = split(/:/,$self->{'roster'}->{$day}->{'sectors'}->[0]->{'RosterRowStartTime'});
			(my $adjyear,my $adjmonth,my $adjday, my $adjhour,my $adjminute,my $adjsecond) = Add_Delta_DHMS(2009,1,1,$hours,$minutes,0,0,-1,0,0);
			push(@{$self->{'roster'}->{$day}->{'RosterRowCheckin'}},sprintf("%02s:%02s",$adjhour,$adjminute));
			
			($hours,$minutes) = split(/:/,$self->{'roster'}->{$day}->{'sectors'}->[$#{$self->{'roster'}->{$day}->{'sectors'}}]->{'RosterRowEndTime'});
			($adjyear,$adjmonth,$adjday,$adjhour,$adjminute,$adjsecond) = Add_Delta_DHMS(2009,1,1,$hours,$minutes,0,0,0,20,0);
			push(@{$self->{'roster'}->{$day}->{'RosterRowCheckout'}},sprintf("%02s:%02s",$adjhour,$adjminute));
			}
			
		}
	
	}

#-------------------------------------------------------------------------------------
# Dumps a planned roster structure in date order
#-------------------------------------------------------------------------------------

sub plannedRoster()
	{
	my $self = shift;

	foreach my $day (sort my_sort keys %{$self->{'roster'}})
		{
		foreach my $sector (@{$self->{'roster'}->{$day}->{'sectors'}})
			{
			print $day." ".$sector->{'RosterRowDep'}." ".$sector->{'RosterRowArr'}."\n";
			}
		}
	}

#-------------------------------------------------------------------------------------
# Dumps a minimal roster from a planned roster as fixed tab text
#-------------------------------------------------------------------------------------

sub miniRoster()
	{
	my $self = shift;

	foreach my $day (sort my_sort keys %{$self->{'roster'}})
		{
		(my $date, my $month, my $year) = split(/ /,$day);
		print Day_of_Week_Abbreviation(Day_of_Week($year,Decode_Month($month),$date))." ";
		print "$date $month ";
		print sprintf('%-6s',$self->{'roster'}->{$day}->{sectors}->[0]->{'RosterRowActivity'})." ";
		print $self->{'roster'}->{$day}->{'RosterRowCheckin'}->[0]." ";
		print @{$self->{'roster'}->{$day}->{'sectors'}}[0]->{'RosterRowDep'}." ";
		my $route = '';
		foreach my $sector (@{$self->{'roster'}->{$day}->{'sectors'}})
			{
			$route .= "$sector->{'RosterRowArr'} ";
			}
		print  sprintf('%-28s', $route);
		print @{$self->{'roster'}->{$day}->{'RosterRowCheckout'}}[$#{$self->{'roster'}->{$day}->{'RosterRowCheckout'}}]."\n";
		}
	}
	
	
#-------------------------------------------------------------------------------------
# Dumps a minimal roster from a planned roster - as a PDF
#-------------------------------------------------------------------------------------

#sub miniRosterPDF()
#	{
#
#	my $self = shift;
#
#	my $pdf = new PDF::Report(PageSize => "A4", PageOrientation => "Landscape");
#
#	$pdf->newpage(1);
#	$pdf->openpage();
#	
#	(my $pagewidth,my $pageheight) = $pdf->getPageDimensions();
#	
#	my $x = 20;
#	my $y = $pageheight-25;
#	my $underline = 'white';
#	my $indent = 0;
#	my $rotate = 0;
#
#	$pdf->setSize(12);
#
#	$pdf->addRawText($self->{'name'},20,$pageheight-30,'black');
#
#	$y-=15;
#
#	$pdf->setSize(8);
#
#	foreach my $day (sort my_sort keys %{$self->{'roster'}})
#		{
#		(my $date, my $month, my $year) = split(/ /,$day);
#
#		$pdf->addRawText(Day_of_Week_Abbreviation(Day_of_Week($year,Decode_Month($month),$date)),$x,$y,'black');
#		$x+=20;
#		$pdf->addRawText("$date $month",$x,$y, 'black');
#		$x+=45;
#		$pdf->addRawText(sprintf('%-6s',$self->{'roster'}->{$day}->{sectors}->[0]->{'RosterRowActivity'}),$x,$y,'black');
#		$x+=40;
#		$pdf->addRawText($self->{'roster'}->{$day}->{'RosterRowCheckin'}->[0], $x,$y,'black');
#		$x+=30;
#		$pdf->addRawText(@{$self->{'roster'}->{$day}->{'sectors'}}[0]->{'RosterRowDep'}, $x,$y,'black');
#		$x+=25;
#		my $route = '';
#		foreach my $sector (@{$self->{'roster'}->{$day}->{'sectors'}})
#			{
#			$route .= "$sector->{'RosterRowArr'} ";
#			}
#		$pdf->addRawText(sprintf('%-28s', $route), $x,$y,'black');
#		$x=300;
#		$pdf->addRawText(@{$self->{'roster'}->{$day}->{'RosterRowCheckout'}}[$#{$self->{'roster'}->{$day}->{'RosterRowCheckout'}}], $x,$y,'black');
#		$x=20;
#		$y-=12;
#		}
#	
#	$pdf->drawRect(10, $pageheight-10 , 330, $y-10);
#	
#	$pdf->saveAs("mini_roster.pdf");
#	}
#	


#-------------------------------------------------------------------------------------
# Comapres two rosters - and prints 'matching' days for pub trips
#-------------------------------------------------------------------------------------
	
sub compareWith()
	{
	my $self = shift;
	my $candidate = shift;

	print "           ".sprintf('%-19s',$self->{'name'}).sprintf('%-20s',$candidate->{'name'})."\n";

	foreach my $day (sort my_sort keys %{$self->{'roster'}})
		{
		(my $date, my $month, my $year) = split(/ /,$day);
		print Day_of_Week_Abbreviation(Day_of_Week($year,Decode_Month($month),$date))." ";
		print "$date $month ";

		print sprintf('%-6s',$self->{'roster'}->{$day}->{sectors}->[0]->{'RosterRowActivity'})." ";
		print $self->{'roster'}->{$day}->{'RosterRowCheckin'}->[0]." ";
		print @{$self->{'roster'}->{$day}->{'RosterRowCheckout'}}[$#{$self->{'roster'}->{$day}->{'RosterRowCheckout'}}]." ";

		print sprintf('%-6s',$candidate->{'roster'}->{$day}->{sectors}->[0]->{'RosterRowActivity'})." ";
		print $candidate->{'roster'}->{$day}->{'RosterRowCheckin'}->[0]." ";
		print @{$candidate->{'roster'}->{$day}->{'RosterRowCheckout'}}[$#{$candidate->{'roster'}->{$day}->{'RosterRowCheckout'}}]."\n";


		}

	
	
	}

#-------------------------------------------------------------------------------------
# Tools for navigating a roster
#-------------------------------------------------------------------------------------


sub firstDay()
	{
	my $self = shift;
	@sortedDays = sort my_sort keys %{$self->{'roster'}};
	$currentDayIndex=0;
	}
	
sub nextDay()
	{
	my $self = shift;
	# print "Next day\n";
	$currentDayIndex+=1;
	}


sub isLastDay()
	{
	my $self = shift;
	return 	($currentDayIndex > $#sortedDays);
	}
	
sub getCheckinTime()
	{
	my $self=shift;
	return $self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'RosterRowCheckin'}->[0];
	}
	
sub getSectorInfo()
	{
	my $self = shift;
	my $info = shift;
	return $self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}->[$currentSectorIndex]->{$info};
	}

sub getCurrentMonthYear()
	{
	my $self = shift;
	# print "Index $currentDayIndex\n";
	return $self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}->[0]->{'RosterRowStartMonth'}." ".$self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}->[0]->{'RosterRowStartYear'};
	#return 'JAN 09';
	}

	
sub firstSector()
	{
	my $self = shift;
	$currentSectorIndex=0;
	return $self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}->[$currentSectorIndex];	
	}
	
sub nextSector()
	{
	my $self = shift;
	# print "Next sector\n";
	$currentSectorIndex+=1;
	return $self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}->[$currentSectorIndex];	
	}

sub isLastSector()
	{
	my $self = shift;
	return ($currentSectorIndex > $#{$self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}});
	}

sub getInfo()
	{
	my $self=shift;
	my $attr = shift;
	return $self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}->[$currentSectorIndex]->{$attr} ? $self->{'roster'}->{$sortedDays[$currentDayIndex]}->{'sectors'}->[$currentSectorIndex]->{$attr} : " ";
	}


#-------------------------------------------------------------------------------------
# Sorts on date from text fields?
#-------------------------------------------------------------------------------------


sub my_sort
	{
	return Delta_Days (Decode_Date_EU($b),Decode_Date_EU($a));
	}

#-------------------------------------------------------------------------------------
# Did it parse OK ?
#-------------------------------------------------------------------------------------

sub parsedOK()
	{
	my $self =shift;
	return $self->{'status'};
	}

#-------------------------------------------------------------------------------------
# Returns ID of staff member to whom this roster belongs
#-------------------------------------------------------------------------------------

sub getMyId()
	{
	my $thing = shift;
	return "$thing->{'staffid'}";
	}

#-----------------------------------------------------------------------------------
# Convert month to number
#-----------------------------------------------------------------------------------

sub monthNum($)
	{
	my $m = shift;
	my $mnum = {'JAN'=>1,'FEB'=>2,'MAR'=>3,'APR'=>4,'MAY'=>5,'JUN'=>6,'JUL'=>7,'AUG'=>8,'SEP'=>9,'OCT'=>10,'NOV'=>11,'DEC'=>12};
	return $mnum->{$m};
	}

#-----------------------------------------------------------------------------------
# Convert num to DOW
#-----------------------------------------------------------------------------------

sub DOW($)
	{
	my @days = ('?','M','T','W','T','F','S','S');
	return $days[shift];
	}

#-----------------------------------------------------------------------------------
# Is this day SAT or SUN
#-----------------------------------------------------------------------------------

sub getDayClass
	{
	my $wday = shift;
	return ($wday < 6) ? 'class="day"' : 'class=we"';
	}

#-----------------------------------------------------------------------------------
# Login
#-----------------------------------------------------------------------------------

sub login
	{
	my $self = shift;
	
	my $mech = shift;
	
	$mech->get('http://crewweb.loganair.co.uk/cwp_wa');
	$mech->field('ctrlUserName',$self->{'staffid'});
	$mech->field('ctrlPassword',$self->{'password'});
	# $mech->submit();
	$mech->click_button(name => "btnLogin");
	}

#-----------------------------------------------------------------------------------
# Logout
#-----------------------------------------------------------------------------------

sub logout
	{
	my $self = shift;
	my $mech = shift;
	$mech->get('http://crewweb.loganair.co.uk/cwp_wa/CWP_LogOut.aspx');
	$mech->submit();
	}

#-----------------------------------------------------------------------------------
# Generel debug 
#-----------------------------------------------------------------------------------

sub examine
	{
	my $self = shift;
	my $para = shift;
	print $self->{'staffid'}."\n";
	print $para."\n";
	}


sub dumpRoster()
	{
	my $self = shift;
	my $file = shift;
	
	open(DEBUGFILE, ">$file") or die("Cannot open file '$file' for writing\n");
	
	print DEBUGFILE Dumper($self);
	
	close DEBUGFILE;
	
	}
1;








