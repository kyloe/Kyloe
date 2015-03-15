package Kyloe::Utils;

use strict;
use warnings;
use base qw( Exporter );

our @EXPORT = qw(doSQL getOneVal getArrayRef checkRunStatus log dbSafeURL clicky getConfigParam);

use DBI;   

#-----------------------------------------------------------------------------------
# Globals
#-----------------------------------------------------------------------------------

my $loglevel=4;
my $workername = "Logger";

#-----------------------------------------------------------------------------------
# Set up DB conection
#-----------------------------------------------------------------------------------

my $dsn = 'DBI:mysql:class:localhost';
my $db_user_name = 'root';
my $db_password = 'fishbodge';
my $dbh = DBI->connect($dsn, $db_user_name, $db_password);

#-----------------------------------------------------------------------------------
# BELOW HERE ARE UTILITY FUNCTIONS
#-----------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------
# Utility to tidy up SQL calls
#-----------------------------------------------------------------------------------

 sub doSQL
	{
	my ($sql) = @_;
	my $sth = $dbh->prepare($sql) or die "Couldnt prepare $sql\n";
	$sth->execute() or die "Failed to exec $sql\n";
	return $sth;
	}

#-----------------------------------------------------------------------------------
# Wrapper for getting a single value
#-----------------------------------------------------------------------------------

sub getOneVal
	{
	my ($sql) = @_;
	my $retVal = '';
	my $sth = doSQL($sql);
	if ($sth->rows > 0)
		{
		$retVal = $sth->fetchrow_array();
		}
	if ($sth->{Active}) {$sth->finish();}
	return $retVal;

	}

#-----------------------------------------------------------------------------------
# Wrapper for getting an array ref
#-----------------------------------------------------------------------------------

sub getArrayRef
	{
	my ($sql) = @_;
	my $sth = &doSQL($sql);
	my @retVal = ();

	if ($sth->rows > 0)
		{
		my $tmpArr;
		while($tmpArr = $sth->fetchrow_hashref())
			{
			push(@retVal,$tmpArr)
			}
		}
	if ($sth->{Active}) {$sth->finish();}
	return @retVal;

	}


#-----------------------------------------------------------------------------------
# Look to see if we should do a graceful exit
#-----------------------------------------------------------------------------------

sub checkRunStatus
	{

	my $sth = &doSQL(qq{select run_status from config});
	my $run_status = $sth->fetchrow_array();
	if ($sth->{Active}) {$sth->finish();}
	return $run_status;

	}

#-----------------------------------------------------------------------------------
# Create a log entry in the database
#-----------------------------------------------------------------------------------

sub log
	{
	my ($level,$text) = @_;
	if ($level < $loglevel)
		{
		my $sql = qq{insert into log (log_agent,log_text, log_date, log_level) values (\'$workername\',\'$text\',NOW(),$level)};
		# print $sql;
		my $sth = &doSQL($sql);
		if ($sth->{Active}) {$sth->finish();}
		}
	}

#-----------------------------------------------------------------------------------
# Escapes single quotes
#-----------------------------------------------------------------------------------


sub dbSafeURL {
	my ($url) = @_;
	$url =~ s/\'/\\\'/g;
	#'
	# print "$url\n";
	return  $url;
	}

#-----------------------------------------------------------------------------------
# Make a url clickable in the log
#-----------------------------------------------------------------------------------

sub clicky
	{
	my ($url) = @_;
	#'
	# print "$url\n";
	return  '<a href="'.$url.'" target="_blank">'.$url.'</a>';
	}

#-----------------------------------------------------------------------------------
# Get config params
#-----------------------------------------------------------------------------------

sub getConfigParam
	{
	my ($param_name, $default) = @_;

	my $sth = &doSQL(qq{select config_param_value from config_params where config_param_name = \'$param_name\'});

	if ($sth->rows > 0)
		{
		return $sth->fetchrow_array();
		}
	else
		{
		return $default;
		}
	}


1;