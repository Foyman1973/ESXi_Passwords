<#        
    .SYNOPSIS
     A brief summary of the commands in the file.

    .DESCRIPTION
    A detailed description of the commands in the file.

    .NOTES
    ========================================================================
         Windows PowerShell Source File 
         
         NAME: Set-NewHostPassword.ps1
         
         AUTHOR: Jason Foy 
         DATE  : 2/22/2019
         
		 COMMENT: ESXi 6.x+ and vCenter ONLY!
		 			Select a cluster from vCenter and set new ROOT password on all cluster members
         
    ==========================================================================
#>
Clear-Host
$Version = "1.3"
$ScriptName = $MyInvocation.MyCommand.Name
$scriptPath = Split-Path $MyInvocation.MyCommand.Path
$reportFolder = Join-Path -Path $scriptPath -ChildPath "Reports"
if(!(Test-Path $reportFolder)){New-Item -ItemType Directory -Path $reportFolder}
$traceFile = Join-Path -Path $reportFolder -ChildPath "$ScriptName.trace"
Start-Transcript $traceFile
# $StartTime = Get-Date
$Date = Get-Date -Format g
Write-Host ("=" * 80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host `t`t"$scriptName v$Version"
Write-Host `t`t"Started $Date"
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host "NOTE:" -ForegroundColor Red -NoNewline
Write-Host "This method requires vCenter and ESXi 6.0 or newer to work"
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
<#
	.SYNOPSIS
		Sets ROOT password via vCenter PowerCLI / ESXCLI v2
#>
function Set-RootPassword {
	[CmdletBinding()]
	[OutputType([boolean])]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$HostName,
		[Parameter(Mandatory = $true)]
		[pscredential]
		$NewCredential
	)
	$vmhost = Get-VMHost -Name $HostName
	Write-Host "$((get-date).ToShortTimeString()) : Resetting password for:" -NoNewline -ForegroundColor Yellow;Write-Host $vmhost -ForegroundColor Cyan
	$esxcli = Get-EsxCli -vmhost $vmhost -v2
    $esxcliargs = $esxcli.system.account.set.CreateArgs()
    $esxcliargs.id = $NewCredential.UserName
    $esxcliargs.password = $NewCredential.GetNetworkCredential().Password
    $esxcliargs.passwordconfirmation = $NewCredential.GetNetworkCredential().Password
    return ($esxcli.system.account.set.Invoke($esxcliargs))
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Test-HostLogin {
	param (
		[Parameter(Mandatory=$true)] [pscredential]$HostCred,
		[Parameter(Mandatory=$true)] [string]$HostName
	)
	Write-Host "$((get-date).ToShortTimeString()) : Testing connection on:" -NoNewLine -ForegroundColor Yellow;Write-Host $HostName -ForegroundColor Cyan
	$GoodPwd = $false
	$testConn=Connect-VIServer $HostName -Credential $HostCred -ErrorAction 'silentlycontinue'
	if($testConn){
		$GoodPwd = $true
		Disconnect-VIServer $HostName -Confirm:$false -Force
	}
	return $GoodPwd
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Exit-Script{
	Write-Host "Script Exit Requested, Exiting..."
	Disconnect-VIServer $vConn -Confirm:$false
	Stop-Transcript
	exit
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Get-PowerCLI{
	$pCLIpresent=$false
	Get-Module -Name VMware.VimAutomation.Core -ListAvailable | Import-Module -ErrorAction SilentlyContinue
	try{$pCLIpresent=((Get-Module VMware.VimAutomation.Core).Version.Major -ge 10)}
	catch{}
	return $pCLIpresent
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

if(!(Get-PowerCLI)){Write-Host "* * * * No PowerCLI Installed or version too old. * * * *" -ForegroundColor Red;Exit-Script}
$vCenter = Read-Host "vCenter FQDN or IP:"
Write-Host "Attempting connection to $vCenter..." -ForegroundColor Magenta
$vConn = Connect-VIServer $vCenter -Credential (Get-Credential -Message "Provide vCenter Account with Admin Privilege")
if($vConn){
	Write-Host "Connected" -ForegroundColor Green
	Write-Host ""
	Write-Host "Available Clusters:" -ForegroundColor Yellow
	Write-Host ("=" * 30) -ForegroundColor DarkGreen
	$clusterList = Get-Cluster | Sort-Object Name
	$choice = @{ }
	for ($i = 1; $i -le $clusterList.count; $i++) {
		Write-Host "  $i ...... $($clusterList[$i-1].Name)"
		$choice.Add($i, $($clusterList[$i - 1].Name))
	}
	Write-Host ("=" * 30) -ForegroundColor DarkGreen
	[int]$answer = Read-Host `t"Select Cluster (1-$($clusterList.count))"
	$myCluster = $choice.Item($answer)
	Write-Host ""
	Write-Host "You Selected:" -NoNewline;Write-Host $myCluster -ForegroundColor Magenta
	Write-Host ""
	$ImDone = $false
	$newCred = Get-Credential -UserName "root" -Message "Provide New ESXi ROOT password"
	$myHosts = Get-Cluster $myCluster|Get-VMHost|Where-Object{$_.ConnectionState -match "Connected|Maintenance"}|Sort-Object Name
	Write-Host "Found $($myHosts.Count) ESXi hosts"
	if(($myHosts|Where-Object{$_.version -lt 6}).count){
		Write-Host "There are hosts that are too old for this process, aborting"-ForegroundColor Red
		Exit-Script
	}
	else{Write-Host "ESXi version is 6.x+" -ForegroundColor Green}
	do{
		Write-Host ("="*60) -ForegroundColor DarkGreen
		$newPWD = New-Object System.Management.Automation.Host.ChoiceDescription "&New Password","Assign a new ROOT password to cluster members"
		$checkPWD = New-Object System.Management.Automation.Host.ChoiceDescription "&Check Password","Audit cluster members for a known ROOT password"
		$quitScript = New-Object System.Management.Automation.Host.ChoiceDescription "&Quit","Quit"
		$options = [System.Management.Automation.Host.ChoiceDescription[]]($newPWD, $checkPWD, $quitScript)
		$title = "Select Action" ;$message = "Set a new password, check for known password or exit."
		$result = $host.ui.PromptForChoice($title, $message, $options, 0)
		switch ($result) {
			0{

				$myHosts|ForEach-Object{Write-Host (Set-RootPassword -HostName $_.Name -NewCredential $newCred)}
			}
			1{
				Write-Host "NOTE:" -NoNewline -ForegroundColor Red
				Write-Host "It can take several minutes for newly set passwords to reflect that change."
				Write-Host "If you just set the password using this utility, you may need to wait before this audit works."
				$myHosts|ForEach-Object{Write-Host (Test-HostLogin -HostCred $newCred -HostName $_.Name)}
			}
			2{
				$ImDone=$true
			}
		}
	}
	until($ImDone)
}
else{Write-Host "Failed to Login to $vCenter" -ForegroundColor Red}
Exit-Script
