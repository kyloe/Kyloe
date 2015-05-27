#!/usr/bin/perl
package Kyloe::Service::RaidoRosterToICS;
use DBI;
use Kyloe::Service;
use Kyloe::Raido::Connector::Roster;
use Data::Dumper;

my $connector;
my $dbh = DBI->connect("dbi:Pg:dbname=raido;user=raido;password=raido") or die "Could not connect to database";
my $userList; # a statement handle to allow us to step through users
my $raido;


sub run {

	my $sql = qq/select c.id as i, c.username as u, c.password as p from credentials c, service s where c.service_id = s.id and s.name = 'Raido Roster to ICS'/;
	my $sth = $dbh->prepare($sql);
 	$sth->execute();
	my $users = $sth->fetchall_arrayref({i=>1,u=>1,p=>1});

	foreach my $user ($users)  
		{
	print Dumper($user);
		my $raido = Kyloe::Raido::Connector::Roster->new();
	
		$raido->login($user->{u},$user->{p}) or die "Login failed\n";
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

