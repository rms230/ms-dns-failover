#master and failover IP addresses
$master = "x.x.x.x" 
$fallover = "x.x.x.x"

#System Config
$systemName = "Failover DNS"

#configuration for the DC, Domain Zone and domain name
$dc = "Domain Controller"
$zone = "DNS Zone"
$dnsRecordName = "xxx"

$curentDate = Get-Date

#Email configuration
$recipients = "Robert Spick <robert-spick@live.co.uk>"
$from = "Robert Spick <robert-spick@live.co.uk>"
$failoverEmailSubject = "$systemName has failedover to secondary"
$restoredEmailSubject = "$systemName fallover has reverted back to master"
$smtpServer = "smtp.localhost"

$failoverEmailBody = "$systemName has failedover to secondary with IP address: $fallover at $currentDate"
$restoredEmailBody = "$systemName has reverted back to master with IP address: $master at $currentDate"

#Start failover
$servers = $master,$fallover

Import-Module DNSServer

$primaryRecord = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -RRType A -Name $dnsRecordName

$currentRecord = $primaryRecord.RecordData.IPv4Address.IPAddressToString

$notMaster = ($currentRecord -ne $master)
	

$sendEmail = $FALSE;
Foreach($s in $servers)
{

	#Do a basic ping test before trying anything
  if(!(Test-Connection -Cn $s -BufferSize 16 -Count 1 -ea 0 -quiet))
  {

   "Problem connecting to $s"
   
   ipconfig /flushdns | out-null
   ipconfig /registerdns | out-null
   nslookup $s | out-null

	#re ping the server after flushing the dns
    if(!(Test-Connection -Cn $s -BufferSize 16 -Count 1 -ea 0 -quiet))
    {
		#There's a problem connecting to the server, If we're on the master server and the current server is the master switch to the fallover server
		if (!$notMaster -and ($s -eq $master))
		{
			$old = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -RRType A -Name $dnsRecordName
			$new = $old.Clone()

			$new.RecordData.IPv4Address = [System.Net.IPAddress]::parse($fallover)
			Set-DnsServerResourceRecord -NewInputObject $new -OldInputObject $old -ZoneName $zone -ComputerName $dc
			
			"Failing over to secondary server $fallover"
			$sendEmail = $TRUE
		}
		
	} else {
		"Resolved problem connecting to $s"
	} #end if

   } else {
		#the server is responding to a ping
		# If the server we are looking at is the master server and we're not running on the master server, switch to the failover server
		if (($master -eq $s) -and $notMaster)
		{
			$old = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -RRType A -Name $dnsRecordName
			$new = $old.Clone()

			$new.RecordData.IPv4Address = [System.Net.IPAddress]::parse($master)
			Set-DnsServerResourceRecord -NewInputObject $new -OldInputObject $old -ZoneName $zone -ComputerName $dc
			
			"Master connectivity issues resolved, reverting back to master."
			$sendEmail = $TRUE
			
			
		}
	
	
   }# end if

} # end foreach

#DO a final check on the DNS and see if we're not on the master record.
$primaryRecord = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -RRType A -Name $dnsRecordName

$currentRecord = $primaryRecord.RecordData.IPv4Address.IPAddressToString

$notMaster = ($currentRecord -ne $master)


if ($sendEmail)
{
	if ($notMaster)
	{
		$emailSubject = $failoverEmailSubject
		$emailBody = $failoverEmailBody
	} else {
		$emailSubject = $restoredEmailSubject
		$emailBody = $restoredEmailBody
	}
	"Sending Email"
	send-mailmessage -to $recipients -from $from -subject $emailSubject -body $emailbody -smtpServer $smtpServer
}

if ($notMaster) {
	"Not running on master, problem. Currently runniung on $currentRecord"
} else {
	"Running on master $currentRecord, no problem."
}
