#!/usr/bin/perl
package Logbook;

use strict;
use warnings;

use Date::Calc qw(:all);
use Data::Dumper;
#use PDF::Report;
use Config::General;
use Kyloe::Roster;
#use Kyloe::OOCBuilder;   
use OpenOffice::OODoc; 


use base qw( Exporter );

our @EXPORT = qw(new versionInfo);

# Function dereference to allow us to use 'strict'

my $func = 
	{
	'date' => \&format_date,
	'time' => \&format_time
	};

#-------------------------------------------------------------------------------------
# Creates a new stub object
#-------------------------------------------------------------------------------------

sub new
	{
	my $class = shift;   # Determine the class for the oject to create
	my $configFile = shift;
	my $staffid = shift;
	my $start = shift;
	my $end = shift;
	
	my $self = {} ;        # Instantiate a generic empty object
	bless $self, $class;  # 'bless' this new generic object into the desired class
		
	my $conf = new Config::General($configFile);
	
	my %hash = $conf->getall();
	$self->{'config'} = \%hash;
	
	$self->openSpreadsheet($self->{'config'}->{'info'}->{'file'}."_".join('_',$staffid,$start,$end,Today()).".ods");

	return $self;         # Return our newly blessed and loaded object
	}
	
#-------------------------------------------------------------------------------------
# Dumps the info section from the config file 
#-------------------------------------------------------------------------------------

sub versionInfo
	{
	my $self = shift;
	
	my $str;
	foreach my $entry (keys %{$self->{'config'}->{'info'}})
		{
		$str.="$entry: $self->{'config'}->{'info'}->{$entry}\n";
		}
	return $str;
	}

#-------------------------------------------------------------------------------------
# Init spreadsheet
#-------------------------------------------------------------------------------------

sub openSpreadsheet
	{
	my $self=shift;
	my $filename = shift;
		
	$self->{'ss'} = odfDocument(
		file => $filename,
		create => "spreadsheet"
		) or die "Failed to create spreadsheet $filename\n";
	print "Creating $filename\n";

	$self->{'currentCol'} = 0;
	$self->{'currentRow'} = 0;
	$self->{'currentSheetName'} = '';
	}
	
	
sub newSheet()
	{
	my $self = shift;
	my $name = shift;
	
	if (!$name) { warn "Sheet not named"; }
	# print "New sheet\n";
	$self->{'ss'}->appendTable($name,75,25);
	my $sheet = $self->{'ss'}->normalizeSheet($name,75,25);
	
	$self->{'currentCol'} = 0;
	$self->{'currentRow'} = 0;
	$self->{'currentSheetName'} = $name;
	$self->{'currentSheetRef'} = $sheet;
	$self->buildHeader();
	}
	
sub nextRow()
	{
	my $self = shift;
	$self->{'currentRow'}++;
	$self->{'currentCol'} = 0;
	}

sub nextCell()
	{
	my $self = shift;
	$self->{'currentCol'}++;
	}


#-------------------------------------------------------------------------------------
# Accepts as Roster object and formats it into a logbook entry
# Mappings from sector entries are handled inthe config file
#-------------------------------------------------------------------------------------
	
sub addExecutedRoster()
	{
	my $self = shift;
	my $roster = shift;
	
	# add one row per roster sector - mapping from Class (e.g. RosterRowActivity) to column from Config file
	
	$roster->firstDay();

	my $currMonthYear = $roster->getCurrentMonthYear();

	print "Create a spreadsheet\n";

	$self->newSheet($currMonthYear);

	print "Process the roster day by day\n";

	while (!$roster->isLastDay())
		{
		
		while (!$roster->isLastDay() && ($currMonthYear eq $roster->getCurrentMonthYear()))
			{
			$roster->firstSector();
			while (!$roster->isLastSector())
				{
				#print $roster->getCheckinTime()." ".$roster->getSectorInfo('RosterRowActivity')."\n";
				$self->appendSector($roster);
				#print "DATE $currMonthYear\n";
				$roster->nextSector();
				}		
			$roster->nextDay();
			}
		print "Processed $currMonthYear\n";
		if (!$roster->isLastDay()) # Need to do this here as the underlying OO interface Creates a new sheet by default
			{	
			$currMonthYear = $roster->getCurrentMonthYear();
			$self->newSheet($currMonthYear);

			}
		}
	# And write out the file
	
	print "Write out file\n";
	
	$self->{'ss'}->save();
	
	}
#-------------------------------------------------------------------------------------
# Build header
#-------------------------------------------------------------------------------------
	
sub buildHeader()
	{
	my $self = shift;
	# For each item in the header config - add an element to the header row

	foreach my $col (@{$self->{'config'}->{'header'}->{'col'}})
		{
		if ($col->{'hide'}) { next };
		$self->{'ss'}->cellValue($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$col->{'label'});

		# TO DO - set widths
		$self->currColWidth($col->{'width'});
		

		$self->nextCell();

		}
	$self->nextRow();
	}
	

#-------------------------------------------------------------------------------------
# Set current column width
#-------------------------------------------------------------------------------------


sub currColWidth
	{
	my $self = shift;
	my $width = shift;
	
	my $styleName = 'Col'.$self->{'currentCol'}.'_'.$width;
	
	if (!$self->{'ss'}->getStyleElement($styleName))
		{
		$self->{'ss'}->createStyle
			( 
			$styleName, 
			family => 'table-column', 
			properties => 
				{ -area => 'table-column', 
				'fo:break-before' => 'auto', 
				'column-width' => $width.'mm' } 
			); 
		}
		
	$self->{'ss'}->columnStyle($self->{'currentSheetRef'}, $self->{'currentCol'}, $styleName); 
	}
	
	

#-------------------------------------------------------------------------------------
# append Sector - adds the current sector in the roster to the next 
# line in the spreadsheet
#-------------------------------------------------------------------------------------

sub appendSector()
	{
	my $self = shift;
	my $roster = shift;
	
	# If this row relates to a non flying activity then skip it
	my $suppress = {DO=>1,APT=>1,SBY=>1,SB1=>1,SB2=>1,MTG=>1,LVE=>1,TAX=>1,HTL=>1,RDO=>1,ADM=>1,SCO=>1, ACO=>1, DS=>1};

	if ($suppress->{$roster->getInfo('RosterRowActivity')})
		{
		return;
		}
	
	foreach my $col (@{$self->{'config'}->{'header'}->{'col'}})
		{
		if ($col->{'hide'}) { next };

		if ($col->{'type'} eq 'formula')
			{
			my $data =  $col->{'value'};
			# row/col is zero based formulas are 1 based - so we must inc them
			my $rowRef = $self->{'currentRow'}+1;
			my $colRef = $self->{'currentCol'}+1;			
			$data =~ s/\$row/$rowRef/gi; 
			$data =~ s/\$col/$colRef/gi;
			
			$self->{'ss'}->cellFormula($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$data);			
			}
		else
			{

			$self->{'ss'}->cellValueType(
				$self->{'currentSheetRef'},
				$self->{'currentRow'},
				$self->{'currentCol'},
				$col->{'type'});

			$self->{'ss'}->cellValue(
				$self->{'currentSheetRef'},
				$self->{'currentRow'},
				$self->{'currentCol'},
				$self->flex_format($roster,$col));
			}

		# if (!$col->{'format'}) {$col->{'format'} = 'General';}
		
##		if ($col->{'value'} =~ /^RosterRow/i)
##			{
##			$self->{'ss'}->cellValueType($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$col->{'type'});
##
##			if ($col->{'format'})
##				{
##				$self->{'ss'}->cellValue($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$self->formatTime($roster->getInfo($col->{'value'}),$col->{'format'}),$roster->getInfo($col->{'value'}));
##				}
##			else	
##				{
##				$self->{'ss'}->cellValue($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$roster->getInfo($col->{'value'}));
##				}
##
##			}
#		elsif ($col->{'type'} eq 'formula')
##			{
#			# Formulas may refer to current row col using ROW and COL variables- so get these vals and substitute them 
#			my $data =  $col->{'value'};
#			# row/col is zero based formulas are 1 based - so we must inc them
#			my $rowRef = $self->{'currentRow'}+1;
#			my $colRef = $self->{'currentCol'}+1;			
#			$data =~ s/\$row/$rowRef/gi; 
#			$data =~ s/\$col/$colRef/gi;
#			
#			$self->{'ss'}->cellFormula($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$data);
#			}
#		elsif ($col->{'type'} eq 'time')
#			{
#			$self->{'ss'}->cellValueType($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$col->{'type'});
#			if ($col->{'format'})
#				{
#				$self->{'ss'}->cellValue(
#					$self->{'currentSheetRef'},
#					$self->{'currentRow'},
#					$self->{'currentCol'},
#					$self->formatTime($roster->getInfo($col->{'value'}),$col->{'format'}),
#					$roster->getInfo($col->{'value'}));
#				}
#			else	
#				{
#				$self->{'ss'}->cellValue($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$roster->getInfo($col->{'value'}));
#				}
#			}
#		else
#			{
#			$self->{'ss'}->cellValueType($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$col->{'type'});
#			$self->{'ss'}->cellValue($self->{'currentSheetRef'},$self->{'currentRow'},$self->{'currentCol'},$col->{'value'});
#			}


		$self->nextCell();
		}	
	$self->nextRow();
	
	}
	
sub flex_format
    {
    my $self = shift;
    my $roster =shift;
    my $col = shift;
   
    
    if ($func->{$col->{type}})
        {
        return &{$func->{$col->{type}}}($self,$roster,$col);
        }
    else
        {
   	return $self->format_($roster,$col);
	}
    }

	
sub format_
	{
	my $self = shift;
	my $roster = shift;
    	my $col = shift;
	return $self->getValue($roster,$col);
	}


sub format_time
	{
	my $self = shift;
	my $roster = shift;
	my $col = shift;

    	# get the data
    	my $vstr;
	my $dstr;
	
    	if ($col->{'format'})
    		{	
		my @data = split(/:/,$self->getValue($roster,$col));

		# parse it

		$vstr = $col->{'format'};
		$vstr =~ s/\$HH\$/$data[0]/;
		$vstr =~ s/\$MM\$/$data[1]/;
		$vstr =~ s/\$SS\$/$data[2]/;
		
		$dstr = $col->{'display'};
		$dstr =~ s/\$HH\$/$data[0]/;
		$dstr =~ s/\$MM\$/$data[1]/;
		$dstr =~ s/\$SS\$/$data[2]/;
		
		return ($vstr,$dstr);
		}
    	else 
    		{
    		return $self->getValue($roster,$col);
    		}
	}
	
sub format_date
	{
	my $self = shift;
	my $roster = shift;
	my $col = shift;

    	# get the data
 	my $vstr;
	my $dstr;
    	
    	if ($col->{'format'})
    		{	
		my @data = split(/:/,$self->getValue($roster,$col));

		# parse it

		$vstr = $col->{'format'};
		$vstr =~ s/\$YYYY\$/$data[0]/;
		my $tdy = substr($data[0],2);
		$vstr =~ s/\$YY\$/$tdy/;
		$vstr =~ s/\$MM\$/$data[1]/;
		$vstr =~ s/\$DD\$/$data[2]/;

		$dstr = $col->{'display'};
		$dstr =~ s/\$YYYY\$/$data[0]/;
		$tdy = substr($data[0],2);
		$dstr =~ s/\$YY\$/$tdy/;
		$dstr =~ s/\$MM\$/$data[1]/;
		$dstr =~ s/\$DD\$/$data[2]/;

		return ($vstr,$dstr);
		}
    	else 
    		{
    		return $self->getValue($roster,$col);
    		}
	}
	
sub getValue
	{
	my $self = shift;
	my $roster = shift;
	my $col = shift;

	my $data;

	if ($col->{'value'} =~ /^RosterRow/i)
		{
		$data = $roster->getInfo($col->{'value'})
		}
	else
		{
		$data = $col->{'value'};
		}

	return $data;    
	}
