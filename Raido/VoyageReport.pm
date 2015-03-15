#!/usr/bin/perl
package Kyloe::Raido::VoyageReport;

use Dancer ':syntax';

#use strict;
use warnings;

use HTML::TreeBuilder;
use Date::Calc qw(:all);
use WWW::Mechanize;
use Data::Dumper;
use Config::General;
use File::Spec;

use DateTime; 
use DateTime::Event::Sunrise;
use DateTime::Format::ISO8601; 

use base qw( Exporter );

our @EXPORT = qw( new asHTML parse getMyId parsedOK compare login);


# new
# login
# retrieveRoster
# parseRoster


#-------------------------------------------------------------------------------------
# State variables for roster navigation
#-------------------------------------------------------------------------------------

my $currentDayIndex = 0;
my $currentSectorIndex = 0;
my @sortedDays;
my $isDancing = 0; # used to decide whether to use dancer style INFO debug

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
	
	# my $conf = new Config::General('/var/services/homes/ian/CloudStation/Projects/Raido/conf/roster.cnf');
	my $conf = new Config::General('/home/ian/CloudStation/Projects/Raido/conf/roster.cnf');
	
	my %hash = $conf->getall();
	$obj->{'config'} = \%hash;
	
	
	$obj->{MECH} = WWW::Mechanize->new();		# The robot
	
	
	return $obj;         # Return our newly blessed and loaded object
	}



#-----------------------------------------------------------------------------------
# Login
#-----------------------------------------------------------------------------------

sub login
{
	my $self = shift;
	my $staffid  = shift;
	my $password = shift;
	
	$self->{MECH}->get($self->{'config'}->{'performed'}->{'loginurl'})
	  or die "Could not get login page";
	$self->{MECH}->form_name('form1') or die "Could not get login form on page ".$self->{'config'}->{'performed'}->{'loginurl'}."\n";
	$self->{MECH}->field( 'txtUserName', $staffid );
	$self->{MECH}->field( 'txtPassword', $password );
	$self->{MECH}->click_button( name => "btnSub" ) or die "Could not click SUBMIT button\n";
	return 1;
}



#--------------------------------------------------------------------------------------
# Retrieve the page with the list of all voyages
#--------------------------------------------------------------------------------------

sub getIndexPage
{
	my $self = shift;


	$self->{MECH}->get($self->{'config'}->{'performed'}->{'allVRurl'}) or die "Could not retrieve voyage report index page";

	$self->{MECH}->form_name("form1");
	$self->{MECH}->field( 'ctl00$CPHcontent$actid','');
	$self->{MECH}->field( 'ctl00$CPHcontent$hidActivityIdsToUpdate', '' );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$dpValidFrom', '06NOV13' );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$dpValidTo', '07NOV13' );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$fAction', '' );
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfCalorder','');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfMonthShortNames','JAN,FEB,MAR,APR,MAY,JUN,JUL,AUG,SEP,OCT,NOV,DEC');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfNewParameter','');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfReadonly','');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfValidFrom','20131106');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfValidTo','20131107');
	$self->{MECH}->field( 'ctl00$CPHcontent$searchdate$hfWdMinNames','Su,Mo,Tu,We,Th,Fr,Sa');
	$self->{MECH}->field( 'ctl00$fAction','');
	$self->{MECH}->submit_form(form_name => 'form1');


	
	return 1;
}

#------------------------------------------------------------------
# Take a response and parse out a list of ID's that will identify 
# All VR's 
#------------------------------------------------------------------

sub getVoyageIDs()
{
	my $self = shift;
	my $dbh = shift;
	
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
		substr($a,0,7);
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
	
	# print Dumper($table_data);
	
	my $rowCount = 0;
	
	# Extract all data from index page - and store in memory structures so that we can re-use MECH to get detail pages

	my $rows;	
	
	for my $r (@{$table_data})
		{
			
		if ($rowCount > 1)
			{
			
			$rows->{$r->[0]->{'VRID'}}->{'comments'} =  		$r->[0]->{'TEXT'};
			$rows->{$r->[0]->{'VRID'}}->{'sector_date'} =  		$r->[1]->{'TEXT'};
			$rows->{$r->[0]->{'VRID'}}->{'airborne_time'} =  	$r->[2]->{'TEXT'};
			$rows->{$r->[0]->{'VRID'}}->{'land_time'} =  		$r->[5]->{'TEXT'};
			$rows->{$r->[0]->{'VRID'}}->{'landing_pilot_name'} =$r->[8]->{'TEXT'};
			$rows->{$r->[0]->{'VRID'}}->{'rainmaker_id'} = 		$r->[8]->{'TEXT'};
										
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
	
	for my $vrid (keys $rows)
	{

		next if ($rows->{$vrid}->{'dep'}) ; # We have already go this one


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
		
		for (my $x=0;$x < $#ranks; $x++)
			{
			$crew->{$ranks[$x]->as_text()} = $crews[$x]->as_text();
			$crew->{$ranks[$x]->as_text()} =~ s/,/ /g; # Replace comma with white space to match old rainmaker format
			$crewComment .= $ranks[$x]->as_text().': '.$crews[$x]->as_text().' ';	 
			}
			
		my @summ = $self->{TREE}->look_down('_tag','span','id',qr/CPHcontent_rptTimes_labFlightInfo_\d/);
		
		my $c = 0;
		
		foreach my $s (@summ)
		{
			my @fields = split(/ /,$s->as_text());
			$rows->{$vrid[$c]}->{'dep'} = $fields[3];
			$rows->{$vrid[$c]}->{'arr'} = $fields[4];
			$rows->{$vrid[$c]}->{'reg'} = $fields[5];
			$rows->{$vrid[$c]}->{'CAP'} = $crew->{'CAP'};
			$rows->{$vrid[$c]}->{'FO'}  = $crew->{'FO'};
			$rows->{$vrid[$c]}->{'CA'}  = $crew->{'CA'};
			$rows->{$vrid[$c]}->{'long text'} = $s->as_text();
			$rows->{$vrid[$c]}->{'comments'} .= $crewComment;
			
			
			
			$c++; 
		}
		
	}
	
	# now process each VR and calculate IDs from Names of crew and aircraft
	# once that has been done 
	# insert sector record
	
	for my $r (keys $rows)
	{
		print "Voyage Report ID $r\n";
  
#		$rows->{$r}->{'landing_pilot_id'} = $self->register($dbh,'person','name',$rows->{$r}->{'landing_pilot_name'});
#		$rows->{$r}->{'p1_id'} = $self->register($dbh,'person','name',$rows->{$r}->{'CAP'});
#		$rows->{$r}->{'p2_id'} = $self->register($dbh,'person','name',$rows->{$r}->{'FO'});
#		$rows->{$r}->{'cc_id'} = $self->register($dbh,'person','name',$rows->{$r}->{'CA'});

#		$rows->{$r}->{'aircraft_id'} = $self->register($dbh,'aircraft','aircraft_reg',$rows->{$r}->{'reg'});
		

		foreach my $f (keys %{$rows->{$r}})
			{
				print $f.'='.$rows->{$r}->{$f}.',' if ($rows->{$r}->{$f});
			}
		print "\n";
	}
		
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
# Generic response parse
#-------------------------------------------------------------------------------------

sub parseRoster()
	{
	my $self = shift;
	my $dbh = shift;
	my $staff_number = shift;
	my $rainmaker_id = '';
	
	$self->parseResponseToTree();
	
	my $table_data = parseTable
			(
			TREE => $self->{TREE}, 
			TABLE_IDENTIFIER => ['class','TableInside'], 
			HEADER_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'ColH'],
			HEADER_ITEM_IDENTIFIER => ['_tag', 'td', 'class', 'ColH'],
			DATA_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'TR'],		
			DATA_ITEM_IDENTIFIER => ['_tag', 'td']		
			);  
	# Insert all new shift records into database

	my $header = \splice(@$table_data,0,1);


	$self->insertShifts($dbh,$table_data);

	# Now for each row - get the detail

	foreach my $row (@$table_data) 
		{
		$self->message("Getting detail for ".@{$row}[0]->{TEXT}."\n");

		$self->getDetailPage(@{$row}[0]->{A});
		
		my $detail = $self->getSectorList();

		$rainmaker_id = @{$row}[0]->{TEXT};
			
		$self->insertSectors($dbh,$rainmaker_id,$detail);

		my $crew = $self->getCrewNames();

		# Add crew references to shift
		
		$self->registerCrew($dbh,$rainmaker_id, $crew);
		
		# Add landing pilot references to shift
		
		my $landers = $self->getLandingRecord();
		
		$self->updateLandingRecord($dbh,$rainmaker_id,$landers);
		

		if ($staff_number)
			{
			# info "Linking to staff number ".$staff_number;
			my $sysId = getID($dbh,'person','staff_number',$staff_number);
			# info "sysId for staff number ".$sysId;
			$self->linkSectorsToLogbook($dbh,$rainmaker_id,$sysId);
			# Now update landing totals
			SQLupdate($dbh,'sector','landing_pilot_id = logbook_id and landed_at_night = 1 ',{land_night=>1});
			SQLupdate($dbh,'sector','landing_pilot_id = logbook_id and landed_at_night = 0 ',{land_day=>1});
			# and apportion hours - if capt - all PIC, else only PIC if landed
			SQLupdate($dbh,'sector','landing_pilot_id = logbook_id ',{hrs_pic=>'hrs_block'},'NOQUOTES');
			SQLupdate($dbh,'sector','logbook_id = p1_id ',{hrs_pic=>'hrs_block'},'NOQUOTES');
			
			}
		else
			{
			info "No staff number supplied - cant link";
			}


		}
		
	
		
	return 1;
	}
	
#-------------------------------------------------------------------------------------
# Register crew - update record with each persons ID 
#-------------------------------------------------------------------------------------

sub registerCrew
	{
	my $self = shift;
	my $dbh = shift;
	my $rainmaker_id = shift;
	my $crew = shift;
	
	foreach my $member (@$crew)
		{
		
		next if (!@{$member}[0]);
		
		my $id = $self->register($dbh,'person','name',@{$member}[1]->{TEXT});
		
		SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{P1_ID=>$id}) if (@{$member}[0]->{TEXT}  =~ /CAP/i);
		SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{P2_ID=>$id}) if (@{$member}[0]->{TEXT}  =~ /FO/i);
		SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{CC_ID=>$id}) if (@{$member}[0]->{TEXT}  =~ /CA/i);
		SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{hrs_instruction=>'hrs_block'},'NOQUOTES') if (@{$member}[2]->{TEXT}  =~ /I/);
		# Whilst reading the crew list we also stashed the staff numbers - so we can update these now
		SQLupdate($dbh,'person','id='.$id,{staff_number=>@{$member}[1]->{TEXTID}});
		}
	}



#-------------------------------------------------------------------------------------
# Update landing record - assigns the landing pilot id from the landing table
#-------------------------------------------------------------------------------------

sub updateLandingRecord
	{
	my $self = shift;
	my $dbh = shift;
	my $rainmaker_id = shift;
	my $landers = shift;
	my $seq = 0;
	
	splice(@$landers,0,1); # ignore blank row at beginning
	
	
	foreach my $landing (@$landers)
		{
		next unless(@{$landing}[2]->{TEXT});
		my $id = $self->register($dbh,'person','name',@{$landing}[2]->{TEXT});
		SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id.' and sector_seq = '.$seq,{Landing_Pilot_ID=>$id});
		
		$seq++;
		}
	}

#-------------------------------------------------------------------------------------
# Link sectors to log book
#-------------------------------------------------------------------------------------

sub linkSectorsToLogbook
	{
	my $self = shift;
	my $dbh = shift;
	my $rainmaker_id = shift;
	my $staff_number = shift;
	

	return SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{logbook_id=>$staff_number});
	
	}
	


#-------------------------------------------------------------------------------------
# Register  - gets ID for item from lookup table - if not found - inserts and gets ID
#-------------------------------------------------------------------------------------

sub register
	{
	my $self = shift;
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
	
	
#-------------------------------------------------------------------------------------
# Inserts one record for each voyage report in the main index page
#-------------------------------------------------------------------------------------

sub insertShifts()
	{
	my $self = shift;
	my $dbh = shift;
	my $data_arr = shift;
	
	foreach my $row (@$data_arr) # use splice to ignore header row
		{
		# build and run an insert command
		
		SQLinsert
			($dbh,'comment',
				{
				Rainmaker_ID => @{$row}[0]->{TEXT},
				Sector_seq => 	0, #comment is always attached to first sector of day - a fudge due to rainmaker data structure
				Comments => 	sqlQuoteSafe(@{$row}[9]->{TEXT})
				}
			);
		}
	}

#-------------------------------------------------------------------------------------
# make a sector record from the detail from the page retrieved
#-------------------------------------------------------------------------------------

sub insertSectors()
	{
	my $self = shift;
	my $dbh = shift;
	my $rainmaker_id = shift;
	my $detail = shift;
	
	splice(@$detail,0,1);
	
	my $seq = 0;
	
	foreach my $row (@$detail)
		{
		
		my $sector_date = formatDate(@{$row}[1]->{TEXT});
		my $dep = textTimetoText(@{$row}[11]->{TEXT});
		my $arr = textTimetoText(@{$row}[14]->{TEXT});
		
		SQLinsert
			($dbh,'sector',
				{
				Sector_Date => 		$sector_date,
				Rainmaker_ID => 	$rainmaker_id,
				Sector_seq =>   	$seq,
				Dep => 			@{$row}[4]->{TEXT},
				Arr => 			@{$row}[5]->{TEXT},
				Dep_Time => 		$dep,
				Airborne_Time =>	textTimetoText(@{$row}[12]->{TEXT}),
				Land_Time => 		textTimetoText(@{$row}[13]->{TEXT}),
				Arr_Time => 		$arr,
				
				Hrs_Block => 		textTimetoDecimal(@{$row}[15]->{TEXT}),
				Hrs_Airborne => 	textTimetoDecimal(@{$row}[16]->{TEXT}),
				hrs_night => 		0,
				hrs_ifr => 		textTimetoDecimal(@{$row}[15]->{TEXT}),
				hrs_pic => 		0,
				hrs_copilot => 		0,
				hrs_dual => 		0,
				hrs_instruction => 	0,
				hrs_sim => 		0
				}
			);

		# Link to A/C table
		
		my $id = $self->register($dbh,'aircraft','Aircraft_reg',@{$row}[3]->{TEXT});
		SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{Aircraft_ID=>$id});
		
		# Calculate night hours and landings
		
		my ($h,$l) = getNightHours(getSectorDateTimes($sector_date,$dep,$arr),getSunriseSunset($sector_date));

		# and use to update the database 

		if ($h)
			{
			SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{hrs_night=>$h});
			}

		if ($l)
			{
			SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{landed_at_night=>1});
			}
		else 	
			{
			SQLupdate($dbh,'sector','Rainmaker_id='.$rainmaker_id,{landed_at_night=>0});
			}

		$seq++;

		}
	}

	
#-------------------------------------------------------------------------------------
# Use the detail URL to get the table of detailed info
#-------------------------------------------------------------------------------------

sub getDetailPage
	{
	my $self = shift;
	my $url = shift;
	$self->{MECH}->get($url);

	$self->parseResponseToTree();

	return 1;	
	}
	
	
	
sub getSectorList
	{
	my $self = shift;

	my $p = sub 
		{
		my $t = shift;
		return substr($t,-4,4);
		};

	my $table_data = parseTable
			(
			TREE => $self->{TREE}, 
			TABLE_IDENTIFIER => ['id','Table12'], 
			HEADER_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'ColH'],
			HEADER_ITEM_IDENTIFIER => ['_tag', 'td', 'class', 'ColH_T'],
			DATA_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'TR'],		
			DATA_ITEM_IDENTIFIER => ['_tag', 'td'],
			PARSER => {11=>{TEXT=>$p},10=>{TEXT=>$p}}
			);

	return $table_data;

	}
	
sub getCrewNames
	{
	my $self = shift;
	
	my $p = sub 
		{
		my $t = shift;
		$t =~ s/\(\D+\)//g; # remove nicknames e.g. UTTING (Kevin) Syd becomes UTTING Syd
		return substr($t,0,index($t,'('));
		};


	my $q = sub 
		{
		my $t = shift;
		$t =~ s/\(\D+\)//g; # remove nicknames e.g. UTTING (Kevin) Syd becomes UTTING Syd
		return substr($t, index($t,'(')+1, index($t,')') - index($t,'(')-1 );
		};

	
	my $table_data = parseTable
			(
			TREE => $self->{TREE}, 
			TABLE_IDENTIFIER => ['id','Table12'], 
			HEADER_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'ColH'],
			HEADER_ITEM_IDENTIFIER => ['_tag', 'td', 'class', 'ColH_T'],
			DATA_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'TR'],		
			DATA_ITEM_IDENTIFIER => ['_tag', 'td'],
			# PARSER => {1=>'substr($text,0,index($text,\'(\'))',1_1=>'substr($text_1,  index($text_1,\'(\')+1,  index($text_1,\')\')-index($text_1,\'(\') -1 )'},
			PARSER => {1=>{TEXT=>$p,TEXTID=>$q}},
			INDEX => 4,
			);

	return $table_data;
	}

	
sub getLandingRecord
	{
	my $self = shift;
	
	my $p = sub 
		{
		my $t = shift;
		substr($t,0,index($t,'('));
		};
	
	my $table_data = parseTable
			(
			TREE => $self->{TREE}, 
			TABLE_IDENTIFIER => ['id','Table12'], 
			HEADER_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'ColH'],
			HEADER_ITEM_IDENTIFIER => ['_tag', 'td', 'class', 'ColH_T'],
			DATA_ROW_IDENTIFIER => ['_tag', 'tr', 'class', 'TR'],		
			DATA_ITEM_IDENTIFIER => ['_tag', 'td'],
			PARSER => {0=>{TEXT=>$p}},
			INDEX => 3,
			);

	return $table_data;

	}



	
#-------------------------------------------------------------------------------------
# Generic SQL functions 
#-------------------------------------------------------------------------------------
	
	
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
# Drops out all data as a CSV file
#-------------------------------------------------------------------------------------
	

sub dumpDataAsCSV
	{
	my $data_arr = shift;
	my $comma = '';	

	my $str;
	

	foreach my $row (@$data_arr)
	
		{
		my $comma = '';	
		foreach my $row_item (@{$row})
			{
			my $qstr = qQuoteSafe($row_item->{TEXT});
			$str .= $comma.$qstr;
			# $str .= $comma.$row_item;
			$comma = ',';	
			}
			
		$str .="\n";
		}
		
	$comma = '';		
	
	return $str;
	
	}

#-------------------------------------------------------------------------------------
# Translates any stray " into ' then double quotes for CSV use in generic imports
#-------------------------------------------------------------------------------------


sub qQuoteSafe
	{
	my $str = shift;
	$str =~ s/\"/\'/g;
	return '"'.$str.'"';
	}
#-------------------------------------------------------------------------------------
# Translates any stray ' into \' 
#-------------------------------------------------------------------------------------


sub sqlQuoteSafe
	{
	my $str = shift;
	$str =~ s/\'/\'\'/g;
	return $str;
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
# Convert month to number and back 
#-----------------------------------------------------------------------------------

sub monthNum($)
	{
	my $m = shift;
	my $mnum = {'JAN'=>1,'FEB'=>2,'MAR'=>3,'APR'=>4,'MAY'=>5,'JUN'=>6,'JUL'=>7,'AUG'=>8,'SEP'=>9,'OCT'=>10,'NOV'=>11,'DEC'=>12};
	return $mnum->{$m};
	}
	


#-----------------------------------------------------------------------------------
# Convert text time format HHMM or HMM to a decimal number of hours 
#-----------------------------------------------------------------------------------

sub textTimetoDecimal
	{
	
	my $time = shift;

	# Lets check this data - RM is well flaky
	
	$time = "0000" if (length($time) < 3); 
	
	my $minutes = substr($time,-2);
	my $hours = substr($time,0,length($time)-2);
	
	# my $dec = ($hours+$minutes/60)/24; # as a fraction of a day 
	my $dec = ($hours+$minutes/60); # as a fraction of an hour 

	return $dec;
	}


#-----------------------------------------------------------------------------------
# Display a decimal number of hours as a time HH:MM
#-----------------------------------------------------------------------------------

sub textTimetoText
	{
	my $time = shift;
	
	# Added to cover duff data in RainMaker
	
	$time = "0000" if (length($time) < 3);
	
	my $minutes = substr($time,-2);
	my $hours = substr($time,0,length($time)-2);
	
	$hours = '0'.$hours if (length($hours) == 1);
	
	return $hours.':'.$minutes;
	}
	
#-----------------------------------------------------------------------------------
# convert date in format dd/mm/yyyy to yyy-mm-dd for database storage
#-----------------------------------------------------------------------------------

sub formatDate
	{
	my $date = shift;
	
	
	
	my @date_arr = split('/',$date);
	return $date_arr[2].'-'.$date_arr[1].'-'.$date_arr[0];
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
# Calculate number of night hours asa decimal - and the number (1 or 0) of night landings
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
		# Its all in the day
		return (0,0,0); # all day time - day landing
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
# Logout
#-----------------------------------------------------------------------------------

sub logout
	{
	my $self = shift;
	$self->{MECH}->get($self->{config}->{performed}->{'logouturl'});
	}

#-----------------------------------------------------------------------------------
# Generel debug 
#-----------------------------------------------------------------------------------

#------------------------------------------------------------------------------------
# Tell the system we're dancing
#-------------------------------------------------------------------------------------

sub letsDance()
	{
	$isDancing = 1;
	}

#-------------------------------------------------------------------------------------
# Tell the system we're not dancing
#-------------------------------------------------------------------------------------

sub stopDancing()
	{
	$isDancing = 0;
	}
	
#-------------------------------------------------------------------------------------
# Are we dancing
#-------------------------------------------------------------------------------------

sub areWeDancing()
	{
	return $isDancing;
	}




sub message()
	{
	my $self = shift;
	my $message = shift;
	if ($self->{config}->{global}->{verbose} eq 'Y')
		{
		info $message;
		}
	}

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
	
	#	print Dumper($args{TREE});
	
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

	




1;








