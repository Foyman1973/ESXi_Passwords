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
         
         COMMENT: Select a cluster from vCenter and set new ROOT password on all cluster members
         
    ==========================================================================
#>

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
$newCred = Get-Credential -UserName "root" -Message "Provide New ESXi ROOT password"


$myHosts = Get-Cluster SEA-VC-NPRD|Get-VMHost|?{$_.ConnectionState -match "Connected|Maintenance"};$myHosts.Count

$myHosts|%{Write-Host (Set-RootPassword -HostName $_.Name -NewCredential $newCred)}

$myHosts|%{Write-Host (Test-HostLogin -HostCred $newCred -HostName $_.Name)}

