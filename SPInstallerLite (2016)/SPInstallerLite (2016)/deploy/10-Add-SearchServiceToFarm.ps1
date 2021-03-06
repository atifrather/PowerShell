 Param
	(
	[Parameter(Mandatory=$True, HelpMessage="You must provide a platform suffix so the script can find the paramter file!")]
	[string]$Platform
	)

<#
	this script will setup the search service for sharepoint. simples.
	this script assumes a single database server, a further script will be required to scale out the architecture.
	some elements of this script are from Technet
#>

# let's clean the error variable as we are not starting a fresh session
$Error.Clear()

# setup the parameter file
$parameterfile = "r:\powershell\xml\spconfig-"+$Platform+".xml"

#REGION load snapins and assemblies
# check for the sharepoint snap-in. this is from Ed Wilson.
$snapinsToCheck = @("Microsoft.SharePoint.PowerShell") #you can add more snapins to this array to load more
$currentSnapins = Get-PSSnapin
$snapinsToCheck | ForEach-Object `
    {$snapin = $_;
        if(($CurrentSnapins | Where-Object {$_.Name -eq "$snapin"}) -eq $null)
        {
            Write-Host "$snapin snapin not found, loading it"
            Add-PSSnapin $snapin
            Write-Host "$snapin snapin loaded"
        }
    }
#ENDREGION

#REGION variables
# get the variables from the parameter file
Try {
	# here we are turning a non-terminating error into a terminating error if the file does not exist, this is so we can catch it
	[xml]$configdata = Get-Content $parameterfile -ErrorAction Stop
}
Catch {
	Write-Warning "There is no parameter file called $parameterfile!"
	Break
}

# stub the variables to make the following lines shorter
$searchServiceConfig = $configdata.farm.searchconfig

# set the variables we need
$databaseServerName = $searchserviceconfig.sqlserver
$searchSAName = $searchserviceconfig.searchsaname
$saAppPoolName = $searchserviceconfig.apppool
$searchDBName = $searchserviceconfig.searchdatabase
$SearchAdminServerName = $searchServiceConfig.searchadminserver
$contentaccessaccountuser = $searchServiceConfig.contentaccessaccount.user
$contentaccessaccountpassword = ConvertTo-SecureString $searchServiceConfig.contentaccessaccount.password -AsPlaintext -Force 
$indexpath = ($searchServiceConfig.indexlocation).Split(":")

#ENDREGION

#REGION Function Declaration
# In this region we are showing the declaration of functions that will be called later in the script.
# This time we're passing parameters into some of the functions using the simplest approach.
# In these examples we are showing how to correctly construct the beginning of a function to include information
# about the funtion that is useful to the reader and that can be invoked from the command line such as a description, examples or notes.
# Muy bueno!

# in this example you can see one of the ways we can pass a parameter into a function
# this approach is the simplest way and gives us none of the goodies we get when we use a param block

Function Test-SPApplicationPoolExists ($apppooltotest) {
	<#
	   .Synopsis
	    This function test the existence of an application pool
	   .Description
	    This function test the existence of an application pool within a SharePoint 
		farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	Test-SPApplicationPoolExists
	   .Notes
	    NAME:  Test-SPApplicationPoolExists
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	# check the app pool exists as it is required for SA creation
	Write-Host
	Write-Host "INFO: Checking Application Pool..." 
	$CheckAppPool = Get-SPServiceApplicationPool -Identity $apppooltotest -erroraction silentlycontinue
		if ($CheckAppPool -eq $null) {
			Write-Warning "Application Pool does not exist, please create. Exiting!"
			Break
		}
		else {	
			Write-Host
			Write-Host "SUCCESS: Application Pool exists, continuing script!" -BackgroundColor DarkGreen
			Write-Host
		}
}

# why are we wrapping the below into functions? because we can and probably should!
# we're using the lazy argument pass into the functions as opposed to having well-formed
# param blocks.  shame on me eh?

Function Start-SPFarmSearchServiceInstances {
		<#
	   .Synopsis
	    This function starts the Search Service instances in the farm
	   .Description
	    This function starts the Search Service instances within a SharePoint 2016
		farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	Start-SPFarmSearchServiceInstances
	   .Notes
	    NAME:  Start-SPFarmSearchServiceInstances
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>

	# start search instances
	Write-Host "INFO: Starting Search Service instances..." 
	Write-Host 
	foreach ($searchinstance in $searchserviceconfig.searchinstances.instance) {
		$instancealreadyonline = Get-SPEnterpriseSearchServiceInstance $searchinstance -ErrorAction SilentlyContinue
		if ($instancealreadyonline.Status -eq "Disabled") {
			Write-Host "INFO: Starting Search Service instance on $searchinstance, please wait." -NoNewline 
			Start-SPEnterpriseSearchServiceInstance $searchinstance
			do {
				sleep -Seconds 2
				$instancestarted = Get-SPEnterpriseSearchServiceInstance $searchinstance
				$instancestartedcheck = $instancestarted.Status
				Write-Host "." -NoNewline 
			} 
			while ($instancestartedcheck -ne "Online")
			Write-Host "Done!" -BackgroundColor DarkGreen
			Write-Host
		}
		$instancealreadyonline = Get-SPEnterpriseSearchQueryAndSiteSettingsServiceInstance $searchinstance -ErrorAction SilentlyContinue
		if ($instancealreadyonline.status -eq "Disabled") {
			Write-Host "INFO: Starting Query and Site Settings instance on $searchinstance, please wait." -NoNewline 
			Start-SPEnterpriseSearchQueryAndSiteSettingsServiceInstance $searchinstance
			do {
				sleep -Seconds 2
				$instancestarted = Get-SPEnterpriseSearchQueryAndSiteSettingsServiceInstance $searchinstance
				$instancestartedcheck = $instancestarted.Status
				Write-Host "." -NoNewline 
			} 
			while ($instancestartedcheck -ne "Online")
			Write-Host "Done!" -BackgroundColor DarkGreen
			Write-Host
		}
	}
	if (!$Error) {
		Write-Host "SUCCESS: Successfully started Search service instances." -BackgroundColor DarkGreen
	}
	else {
		Write-Warning "Unable to start Search Service instances. The error was: $error"
		Write-Warning "Exiting Script!"
		Break
	}
}

Function New-SPSearchServiceApplication ($serviceappname) {
	<#
	   .Synopsis
	    This function creates the Search Service Application in the farm
	   .Description
	    This function creates the Search Service Application within a SharePoint 2016
		farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
		If you want to test this function repeatedly and need to remove the SA you can use:
		Get-SPEnterpriseSearchServiceApplication | Remove-SPEnterpriseSearchServiceApplication -RemoveData -Confirm:$false
	   .Example
	   	New-SPSearchServiceApplication
	   .Notes
	    NAME:  New-SPSearchServiceApplication
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>

	# continuing with SA creation
	Write-Host
	Write-Host "INFO: Creating Search Service Application..." -NoNewline 
	$testforsa = Get-SPEnterpriseSearchServiceApplication -Identity $serviceappname -ErrorAction SilentlyContinue
	if ($testforsa -eq $null) {
		$searchserviceapp = New-SPEnterpriseSearchServiceApplication -Name $serviceappname -ApplicationPool $saAppPoolName -DatabaseServer $databaseServerName -DatabaseName $searchDBName
		$searchInstance = Get-SPEnterpriseSearchServiceInstance $SearchAdminServerName
		Write-Host "Done!" -BackgroundColor DarkGreen
		#  Proxy
		Write-Host
		Write-Host "INFO: Creating Service Application Proxy..." -NoNewline 
		$searchserviceappproxy = New-SPEnterpriseSearchServiceApplicationProxy -Name "$searchSAName Proxy" -SearchApplication $searchserviceapp
		Write-Host "Done!" -BackgroundColor DarkGreen
		Write-Host 
#		Write-Host "INFO: Creating Administration Component..." -NoNewline 
#		$searchserviceapp | Get-SPEnterpriseSearchAdministrationComponent | Set-SPEnterpriseSearchAdministrationComponent -SearchServiceInstance $searchInstance
#		Write-Host "Done!" -BackgroundColor DarkGreen
		$Error.Clear()
	}
	else {
		Write-Host "INFO: Service Application $serviceappname already exists, continuing..." 
		Write-Host
	}
	if (!$Error) {
		Write-Host
		Write-Host "SUCCESS: Successfully created Search Service Application." -BackgroundColor DarkGreen
	}
	else {
		Write-Warning "Unable to create Search Service Application. The error was: $error"
		Write-Warning "Exiting Script!"
		Break
	}
}

Function Test-SPSearchAdminOnline {
	<#
	   .Synopsis
	    This function tests to ensure that the Search Admin Component is online
	   .Description
	    This function tests to ensure that the Search Admin Component is online within a SharePoint 2016 farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
		If you want to test this function repeatedly and need to remove the SA you can use:
		Get-SPEnterpriseSearchServiceApplication | Remove-SPEnterpriseSearchServiceApplication -RemoveData -Confirm:$false
	   .Example
	   	Test-SPSearchAdminOnline
	   .Notes
	    NAME:  Test-SPSearchAdminOnline
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>

	Write-Host
	write-host 'INFO: Waiting until Search Administration comes online before continuing...'  -NoNewline
	do {
		sleep -Seconds 3
		# when you are using tests such as this do...while loop - you can discover the properties you can test against by piping the output of a get cmdlet (such as the one below)
		# into a Get-Member.  This will tell you what you can test against. Handy!
		$searchadminstarted = (Get-SPEnterpriseSearchServiceApplication -Identity $searchSAName | Get-SPEnterpriseSearchAdministrationComponent -ErrorAction SilentlyContinue)
		$searchadminstartedcheck = $searchadminstarted.Initialized
		Write-Host '.' -NoNewline
	} 
	while ($searchadminstartedcheck -ne $true)
	Write-Host 'Done!' -BackgroundColor DarkGreen
	Write-Host
	Write-Host 'SUCCESS: Search Admin Online!' -BackgroundColor DarkGreen
}

Function Restart-SPTimerServiceOnAllFarmServers {
	<#
	   .Synopsis
	    This function (guess what?) restarts the timer service.
	   .Description
	    This function restarts the timer service on all SharePoint servers within a SharePoint 2016 farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	Restart-SPTimerServiceOnAllFarmServers
	   .Notes
	    NAME: Restart-SPTimerServiceOnAllFarmServers
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>

	Write-Host
	# sometimes we just need to restart the timer service to get everything squared away. i wish i knew why.
	# its just a fact of SharePoint life :(
	Write-Host "INFO: Restarting Timer Service on all farm servers..." 
	Write-Host
	foreach ($farmserver in $configdata.farm.servers.childnodes) {
		Write-Host "INFO: Stopping $((Get-Service SPTimerV4).DisplayName) Service on $($farmserver.Name)..." -NoNewline 
		Stop-Service -inputobject $(Get-Service -ComputerName $farmserver.Name -Name "SPTimerV4")
		If (!$?) {
			Throw "Could not stop Timer service!"
		}
		Write-Host "Timer Service Stopped!" -BackgroundColor DarkGreen
		Write-Host 
		Write-Host "INFO: Restarting $((Get-Service SPTimerV4).DisplayName) Service on $($farmserver.Name)..." -NoNewline 
		Start-Service -inputobject $(Get-Service -ComputerName $farmserver.Name -Name "SPTimerV4")
		If (!$?) {
			Throw "Could not start Timer service!"
		}
		Write-Host "Timer Service started!" -BackgroundColor DarkGreen
		Write-Host 
	}
	Write-Host 'All timer services in farm restarted!' -BackgroundColor DarkGreen
}

Function Set-SPSearchCrawlAccount ($searchserviceapplication) {
	<#
	   .Synopsis
	    This function sets the default content crawl account.
	   .Description
	    This function sets the default content crawl account within a SharePoint 2016 farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	Set-SPSearchCrawlAccount
	   .Notes
	    NAME: Set-SPSearchCrawlAccount
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	
	# Content Access Account
	Write-Host
	# Do you think some error handling should be in here?
	# Perhaps you can add it yourself? :)
	sleep 5 # we put this here to let the timer service catch up with itself as we are in a demo envrionment
			# this is not required in a fully-powered environment!
	$searchserviceapp = Get-SPEnterpriseSearchServiceApplication -Identity $searchserviceapplication -ErrorAction inquire
	Write-Host "INFO: Setting the default content access account..." -NoNewline 
	$searchserviceapp | Set-SPEnterpriseSearchServiceApplication -DefaultContentAccessAccountName $contentaccessaccountuser -DefaultContentAccessAccountPassword $contentaccessaccountpassword
	Write-Host "Done!" -BackgroundColor DarkGreen
	$Error.Clear()
}

#ENDREGION

# lets start the work of this script
# the steely eyed among you will notice that we are passing parameters, when we
# could have just left the variable names as-is in the function.  It's 
# just for demo purposes so don't have a cow man!

# First, something not in a function - so put it in one!

foreach ($IndexLocation in $searchServiceConfig.searchinstances.instance) {
	if (Test-Path -Path ("\\" + $indexlocation + "\" + $indexpath[0] + "`$" + $indexpath[1])) {
		Remove-Item ("\\" + $indexlocation + "\" + $indexpath[0] + "`$" + $indexpath[1] + "\*") -Recurse
	}
	else {
		Write-Host "Index location does not exist on $indexlocation, please create!"
		Break
	}
}

Test-SPApplicationPoolExists -apppooltotest $saAppPoolName

Start-SPFarmSearchServiceInstances

New-SPSearchServiceApplication -serviceappname $searchSAName

Test-SPSearchAdminOnline

Restart-SPTimerServiceOnAllFarmServers

Set-SPSearchCrawlAccount -searchserviceapplication $searchSAName

# now then happy powershell people.  don't you think it would be a great education
# for you to wrap these final blocks into functions?
# learn by doing Kemosabe, learn by doing!

# Clone Topology
$SearchApp = Get-SPEnterpriseSearchServiceApplication -Identity $searchSAName
$SearchTopology = $SearchApp.ActiveTopology.Clone()

# Provision Search Administration
New-SPEnterpriseSearchAdminComponent -SearchServiceInstance $searchServiceConfig.searchadminserver -SearchTopology $SearchTopology

# Provision Content Processing
New-SPEnterpriseSearchContentProcessingComponent -SearchServiceInstance $searchServiceConfig.searchadminserver -SearchTopology $SearchTopology

# Provision Analytics Processing
New-SPEnterpriseSearchAnalyticsProcessingComponent -SearchServiceInstance $searchServiceConfig.searchadminserver -SearchTopology $SearchTopology

# Provision Crawl
foreach ($SPCrawlServer in $searchServiceConfig.crawlservers.instance) {
	New-SPEnterpriseSearchCrawlComponent -SearchServiceInstance (Get-SPEnterpriseSearchServiceInstance -Identity $SPCrawlServer) -SearchTopology $SearchTopology
}

# Provision Index
# this index location needs to be empty see above for how this is ensured
foreach ($SPIndexServer in $searchServiceConfig.searchinstances.instance) {
	New-SPEnterpriseSearchIndexComponent -SearchServiceInstance (Get-SPEnterpriseSearchServiceInstance -Identity $SPIndexServer) -SearchTopology $SearchTopology -RootDirectory $searchServiceConfig.indexlocation
}

# Provison Query
foreach ($SPQueryServer in $searchServiceConfig.queryservers.instance) {
	New-SPEnterpriseSearchQueryProcessingComponent -SearchServiceInstance (Get-SPEnterpriseSearchServiceInstance -Identity $SPQueryServer) -SearchTopology $SearchTopology
}

# Activate Topology
$SearchTopology.Activate()

# final report
if (!$Error) {
	Write-Host
	Write-Host "SUCCESS: Service Application and topology $searchsaname Created!" -BackgroundColor DarkGreen
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)' completed'.txt
}
else {
	Write-Host
	Write-Warning "There was an error creating the Service Application or its Topology, the error was:"
	Write-Host $Error -ForegroundColor Red
	start-process "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\BIN\psconfigui.exe" -argumentlist "-cmd showcentraladmin"
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)' failed'.txt
}
Write-Host

#    The PowerShell Tutorial for SharePoint 2016
#    Copyright (C) 2015 Seb Matthews
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.