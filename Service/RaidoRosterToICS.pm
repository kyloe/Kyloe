#!/usr/bin/perl
package Kyloe::Service::RaidoRosterToICS;
use DBI;
use Kyloe::Service;
use Kyloe::Raido::Connector::Roster;
 
my $connector;
my $dbh = DBI->connect("dbi:Pg:dbname=raido;user=raido;password=raido") or die "Could not connect to database";
my $userList; # a statement handle to allow us to step through users
my $raido;

sub getUserList {
	#die "getUserList() not implemented";
	# Logon to raido database and get a list of users who 
	# 
	my $sql = qq/select c.id, c.username, c.password from credentials c, service s where c.credential_id = s.id and s.name = 'RaidoRosterToICS'/;
	my $sth = $dbh->prepare($sql);
 	$sth->execute();
}


sub run {

	my $users = $sth->fetchall_arrayref({id=>1,username=>1,password=>1});
	
	foreach my $user ($users)  
		{

		my $raido = Kyloe::Raido::Connector::Roster->new();
	
		$raido->login($user->{username},$user->{password}) or die "Login failed\n";
		$raido->getRoster or die "Couldn't retrieve current roster page\n";
		$raido->getNextMonth or die "Could not retrieve next months roster\n";
		$raido->parseRoster('TREE') or die "Could not parse main roster\n";
		$raido->parseRoster('TREE_2') or die "Could not parse next months roster\n";

		my $sql = qq/select p.name, p.value from parameters p, credentials c, service s where c.parameter_id = p.id AND c.credential_id = s.id AND s.name = 'RaidoRosterToICS'/;
		my $sth = $dbh->prepare($sql);
	 	$sth->execute();
		my $pref = $sth->fetchall_hashref(p.name);
		
		my $params = {staffid => $pref->{staffid}->{value}, password => $pref->{password}->{value},	checkin=>$pref->{checkin}->{value},	altsummary=>$pref->{altsummary}->{value},summary=>$pref->{summary}->{value}};
		$raido->writeICS($params);
		undef $raido;
		}


}

1;

