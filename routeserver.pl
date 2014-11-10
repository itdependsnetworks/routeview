#!/usr/bin/perl

 use Net::Appliance::Session;

my $dir = '/scripts/routeview';

my (@devices)=();
my (@config_in)=();
open(FILE, "$dir/configs") or die("Unable to open file");
@config_in = <FILE>;
close FILE;

my $network_output =();

my (%type,%username,%password,%location,%isp)=();
foreach my $line (@config_in){
	chomp($line);
	if ($line =~ /^#/ || $line =~ /^ / || $line =~ /^$/  ){

	}
	elsif ($line =~ /^networks/i){
		my @splitline = split(/,/,$line);
		push @network, $splitline[1];
		$asn{$splitline[1]} = $splitline[2];
	}
	else {
		my @splitline = split(/,/,$line);
		my $type = $splitline[0];
		my $username = $splitline[1];
		my $password = $splitline[2];
		my $device = $splitline[3];
		my $locataion = $splitline[4];
		my $isp = $splitline[5];

		$type{$device} = $type;
		$username{$device} = $username if $username;
		$password{$device} = $password if $password;
		$location{$device} = $location if $location;
		$isp{$device} = $isp if $isp;
		push @devices, $device;
	}
}


my $session_obj = ();
my %network_last_asn =();

foreach my $device (@devices){

	$network_output .= "Carrier -> $isp{$device} : Location -> $location{$device} \n";
	#print "$device,$username{$device},$password{$device}\n";
	if ($type{$device} eq 'Cisco-Telnet'){
		$session_obj = &cisco_telnet($device,$username{$device},$password{$device});
		if ($session_obj){
			&cmdSend("show ip bgp 127.0.0.1");
			foreach my $network (@network){
#				print "$device $network\n";
				my @command_response = &cmdSend("show ip bgp $network");
				if (@command_response){
					my $parse = &cisco_parse($asn{$network},@command_response);
					my @allasn = split(/\r|\n/,$parse);
					foreach my $allasn (@allasn){
						my @asnsplit = split(/\s+/,$allasn);
						pop(@asnsplit);
						my $lastasn = pop(@asnsplit);	
						$network_last_asn{"$network-$lastasn"} = 1;
						$output = "$device -> Network $network -> ASN Path $allasn -> Last Hop ASN $lastasn\n";# Comment Out if getting full
					}
#					print "@command_response";
#					$output = make_string(@command_response); #Uncomment to get full
				}
				else {
					$output = "No Route Found for $device $network\n";
				}
				$network_output .= $output;	
			}
		}
	}
        elsif ($type{$device} eq 'JUNOS-Telnet'){
                $session_obj = &junos_telnet($device,$username{$device},$password{$device});
                if ($session_obj){
#                        &cmdSend("show ip bgp 127.0.0.1");
                        foreach my $network (@network){
                               #print "$device $network\n";
                                my @command_response = &cmdSend("show route $network detail");
                                if (@command_response){
                                        my $parse = &junos_parse($asn{$network},@command_response);
                                        my @allasn = split(/\r|\n/,$parse);
                                        foreach my $allasn (@allasn){
                                                my @asnsplit = split(/\s+/,$allasn);
                                                pop(@asnsplit);
                                                my $lastasn = pop(@asnsplit);
                                                $network_last_asn{"$network-$lastasn"} = 1;
                                                $output = "$device -> Network $network -> ASN Path $allasn -> Last Hop ASN $lastasn\n";# Comment Out if getting full
                                        }
#                                       print "@command_response";
#                                       $output = make_string(@command_response); #Uncomment to get full
                                }
                                else {
                                        $output = "No Route Found for $device $network\n";
                                }
                                $network_output .= $output;
                        }
                }
        }

}

my $holdnetwork = ();
foreach $key (sort keys %network_last_asn) {
	my @splitkey = split(/-/,$key);
	my $network = $splitkey[0];
	my $asn = $splitkey[1];
#	print "$key\n";
	if ($holdnetwork ne $network){
		$network_output .= "\nNetwork $network, -> ASN Learned from:\n";
	}
	$network_output .= "$asn\n";
	$holdnetwork = $network;
}

my $time = &retTime;
open FILE, ">$dir/output/Networks-$time" or die $!;
	print FILE  $network_output;
#	print $network_output;
close FILE;

sub make_string {
	my @configs = @_;
	my $current_output =();

	foreach my $line (@configs){
		$current_output .= $line;

	}
	return $current_output;
}

sub cisco_parse {
	my $asn = shift;
	my @configs = @_;
	my $out =();

	foreach my $line (@configs){
#		print "AA$line -- $asn -BB\n";
		if ($line !~ /[a-z|A-Z]/) {
			if ($line =~ /(^.+$asn?)\s$/) {
				my $asnpath = $1;
#				print "XXXX $asnpath $asn YYY\n";
				$out .=  "$asnpath\n";
			}
		}
	}
	return $out;

}

sub junos_parse {
        my $asn = shift;
        my @configs = @_;
        my $out =();

        foreach my $line (@configs){
#               print "AA$line -- $asn -BB\n";
#                if ($line !~ /[a-z|A-Z]/) {
                        if ($line =~ /AS path: (.+$asn?) I /) {
                                my $asnpath = $1;
                               #print "XXXX $asnpath $asn YYY\n";
                                $out .=  "$asnpath\n";
                        }
#                }
        }
        return $out;

}

sub cmdSend {
        my $cmd = shift;
        my $debug = 0;
        my (@return,$controllercheck,$start) = ();

	eval {@return = $session_obj->cmd($cmd);};

	if (@return){
		print "--$cmd success\n" if $debug;
        	return @return;
	}
	else {
		print "--$cmd failed\n";
	}

}


sub cisco_telnet {
        my $current_device = shift;
        my $current_username = shift;
        my $current_password = shift;

#	print "$current_device -- $current_username ---- $current_password\n";
	if (!$current_username){
		$current_username = 'user';
	}
	if (!$current_password && $current_username ne 'user'){
#		$current_password = 'password';
	}
	elsif (!$current_password){
		$current_password = 'password';
	}
                sleep(2);
		$session_obj = Net::Appliance::Session->new(
			host      => $current_device,
			personality      => 'ios',
			transport => 'Telnet',
		);

        try {
#		$session_obj->set_global_log_at('debug');
		$session_obj =  $session_obj->connect(
			username => $current_username,  
			password => $current_password,
			Timeout  => 40,
			#SHKC => 0,
		);
	}
	catch {
		$network_output .= "Failed to connect to $current_device\n";
		return 0;
	}
	finally {
		return $session_obj;
	};
}
sub junos_telnet {
        my $current_device = shift;
        my $current_username = shift;
        my $current_password = shift;

#       print "$current_device -- $current_username ---- $current_password\n";
        if (!$current_username){
                $current_username = 'user';
        }
        if (!$current_password && $current_username ne 'user'){
#               $current_password = 'password';
        }
        elsif (!$current_password){
                $current_password = 'password';
        }
                sleep(2);
                $session_obj = Net::Appliance::Session->new(
                        host      => $current_device,
                        personality      => 'junos',
                        transport => 'Telnet',
                );

        try {
#               $session_obj->set_global_log_at('debug');
                $session_obj =  $session_obj->connect(
                        username => $current_username,
                        password => $current_password,
                        Timeout  => 40,
                        #SHKC => 0,
                );
        }
        catch {
                $network_output .= "Failed to connect to $current_device\n";
                return 0;
        }
        finally {
                return $session_obj;
        };
}


sub retTime {
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$date)=();
        ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
        $time = sprintf("%4d-%02d-%02d-%02d-%02d",$year+1900,$mon+1,$mday,$hour,$min);
        return $time;

}

