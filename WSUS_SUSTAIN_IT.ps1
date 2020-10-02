<#   
.SYNOPSIS   
    A collection of fuctions and scripts to forma an interactive program that allows a user to connect to a local or remote server and perform WSUS maintenance.
    Program created using SUP maintaince guid from Microsoft. 
.DESCRIPTION 
    Presents an interactive menu for user to first declare the remote or local machine address. After, selecting a maintenance function from the menu system,
    a connection to the machine is made. The selected a maintenance is then performed on the declared system.    
.NOTES   
    Name: WSUS Sustainment Program
    Author: Jeffery Marugg
    Modifier: N/A
    DateCreated: August 4 2020
    DateModifed: 8/14/2020 
    Warning: Use this at you own risk! Make backups! Create snapshots! I am not responsible for any issues that arises due to the use of this program by anyone other then me.
    I recommend reading the link prvided below, before proceeding. The presumption of this program is the use of NonSSL for all connections. You will need to modify for SSL.     
.LINK   
    https://support.microsoft.com/en-us/help/4490644/complete-guide-to-microsoft-wsus-and-configuration-manager-sup-maint
.DEPENDANCIES
    WSUS_CUSTOM_INDEXING.SQL
    WSUS_DB_MAINT.SQL
    SQLCMD APPLICATION 
  
Description 
----------- 
Presents a text based menu for the user to interactively perform WSUS maintenance on a local or remote machine.    
#> 
Function Do-backup{
$bdir = Test-Path -Path c:\BACKUPS -IsValid
if ($bdir -ne 'True') {
write-host "Creating directory c:\BACKUPS"
mkdir c:\BACKUPS
}
write-host "Creating backup of local SUSDB now"
sqlcmd -E -S \\.\pipe\MICROSOFT##WID\tsql\query -Q "BACKUP DATABASE [SUSDB] TO DISK='C:\BACKUPS\SUSDB.bak'"
write-host ""
write-host "Backup complete!" -foregroundcolor green
write-host "Backup directory c:\BACKUPS"
write-host ""
Pause
.$Lmenu
}
Function Do-CustomIndex{
Write-host ""
sqlcmd -S \\.\pipe\MICROSOFT##WID\tsql\query -i ".\Wsus_custom_indexing.sql"
Write-host ""
Pause
.$Lmenu
}
$outPath = Split-Path $script:MyInvocation.MyCommand.Path
function Do-DeclineSuper {
<#
    .SYNOPSIS
       Decline WSUS superseeded update with exclusion period. 
    .DESCRIPTION
        Not indedependant of this script.
   .NOTES
   Usage:

To do a test run against WSUS Server without SSL
  Decline-SupersededUpdates.ps1 -UpdateServer SERVERNAME -Port 8530 -SkipDecline

To do a test run against WSUS Server using SSL
  Decline-SupersededUpdates.ps1 -UpdateServer SERVERNAME -UseSSL -Port 8531 -SkipDecline

To decline all superseded updates on the WSUS Server using SSL
 Decline-SupersededUpdates.ps1 -UpdateServer SERVERNAME -UseSSL -Port 8531

To decline only Last Level superseded updates on the WSUS Server using SSL
 Decline-SupersededUpdates.ps1 -UpdateServer SERVERNAME -UseSSL -Port 8531 -DeclineLastLevelOnly

To decline all superseded updates on the WSUS Server using SSL but keep superseded updates published within the last 2 months (60 days)
 Decline-SupersededUpdates.ps1 -UpdateServer SERVERNAME -UseSSL -Port 8531 -ExclusionPeriod 60
#>

   [CmdletBinding()]
Param(
#	[Parameter(Mandatory=$True,Position=1)]
#    [string] $server,
	
#	[Parameter(Mandatory=$False)]
#    [switch] $UseSSL,
	
#	[Parameter(Mandatory=$True, Position=2)]
#    $Port,
	
    [switch] $SkipDecline,
	
    [switch] $DeclineLastLevelOnly,
	
    [Parameter(Mandatory=$False)]
    [int] $ExclusionPeriod = 0
)
$Port = 8530
Write-Host ""

if ($SkipDecline -and $DeclineLastLevelOnly) {
    Write-Host "Using SkipDecline and DeclineLastLevelOnly switches together is not allowed."
	Write-Host ""
    return
}

# $outPath = Split-Path $script:MyInvocation.MyCommand.Path
$outSupersededList = Join-Path $outPath "SupersededUpdates.csv"
$outSupersededListBackup = Join-Path $outPath "SupersededUpdatesBackup.csv" 
"UpdateID, RevisionNumber, Title, KBArticle, SecurityBulletin, LastLevel" | Out-File $outSupersededList

try {
    
    if ($UseSSL) {
        Write-Host "Connecting to WSUS server $server on Port $Port using SSL... " -NoNewLine
    } Else {
        Write-Host "Connecting to WSUS server $server on Port $Port... " -NoNewLine
    }
    
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | out-null
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($server, $UseSSL, $Port);
}
catch [System.Exception] 
{
    Write-Host "Failed to connect."
    Write-Host "Error:" $_.Exception.Message
    Write-Host "Please make sure that WSUS Admin Console is installed on this machine"
	Write-Host ""
    $wsus = $null
}

if ($wsus -eq $null) { return } 

Write-Host "Connected."

$countAllUpdates = 0
$countSupersededAll = 0
$countSupersededLastLevel = 0
$countSupersededExclusionPeriod = 0
$countSupersededLastLevelExclusionPeriod = 0
$countDeclined = 0

Write-Host "Getting a list of all updates... " -NoNewLine

try {
	$allUpdates = $wsus.GetUpdates()
}

catch [System.Exception]
{
	Write-Host "Failed to get updates."
	Write-Host "Error:" $_.Exception.Message
    Write-Host "If this operation timed out, please decline the superseded updates from the WSUS Console manually."
	Write-Host ""
	return
}

Write-Host "Done"

Write-Host "Parsing the list of updates... " -NoNewLine
foreach($update in $allUpdates) {
    
    $countAllUpdates++
    
    if ($update.IsDeclined) {
        $countDeclined++
    }
    
    if (!$update.IsDeclined -and $update.IsSuperseded) {
        $countSupersededAll++
        
        if (!$update.HasSupersededUpdates) {
            $countSupersededLastLevel++
        }

        if ($update.CreationDate -lt (get-date).AddDays(-$ExclusionPeriod))  {
		    $countSupersededExclusionPeriod++
			if (!$update.HasSupersededUpdates) {
				$countSupersededLastLevelExclusionPeriod++
			}
        }		
        
        "$($update.Id.UpdateId.Guid), $($update.Id.RevisionNumber), $($update.Title), $($update.KnowledgeBaseArticles), $($update.SecurityBulletins), $($update.HasSupersededUpdates)" | Out-File $outSupersededList -Append       
        
    }
}

Write-Host "Done."
Write-Host "List of superseded updates: $outSupersededList"

Write-Host ""
Write-Host "Summary:"
Write-Host "========"

Write-Host "All Updates =" $countAllUpdates
Write-Host "Any except Declined =" ($countAllUpdates - $countDeclined)
Write-Host "All Superseded Updates =" $countSupersededAll
Write-Host "    Superseded Updates (Intermediate) =" ($countSupersededAll - $countSupersededLastLevel)
Write-Host "    Superseded Updates (Last Level) =" $countSupersededLastLevel
Write-Host "    Superseded Updates (Older than $ExclusionPeriod days) =" $countSupersededExclusionPeriod
Write-Host "    Superseded Updates (Last Level Older than $ExclusionPeriod days) =" $countSupersededLastLevelExclusionPeriod
Write-Host ""

$i = 0
if (!$SkipDecline) {
    
    Write-Host "SkipDecline flag is set to $SkipDecline. Continuing with declining updates"
    $updatesDeclined = 0
    
    if ($DeclineLastLevelOnly) {
        Write-Host "  DeclineLastLevel is set to True. Only declining last level superseded updates." 
        
        foreach ($update in $allUpdates) {
            
            if (!$update.IsDeclined -and $update.IsSuperseded -and !$update.HasSupersededUpdates) {
              if ($update.CreationDate -lt (get-date).AddDays(-$ExclusionPeriod))  {
			    $i++
				$percentComplete = "{0:N2}" -f (($updatesDeclined/$countSupersededLastLevelExclusionPeriod) * 100)
				Write-Progress -Activity "Declining Updates" -Status "Declining update #$i/$countSupersededLastLevelExclusionPeriod - $($update.Id.UpdateId.Guid)" -PercentComplete $percentComplete -CurrentOperation "$($percentComplete)% complete"
				
                try 
                {
                    $update.Decline()                    
                    $updatesDeclined++
                }
                catch [System.Exception]
                {
                    Write-Host "Failed to decline update $($update.Id.UpdateId.Guid). Error:" $_.Exception.Message
                } 
              }             
            }
        }        
    }
    else {
        Write-Host "  DeclineLastLevel is set to False. Declining all superseded updates."
        
        foreach ($update in $allUpdates) {
            
            if (!$update.IsDeclined -and $update.IsSuperseded) {
              if ($update.CreationDate -lt (get-date).AddDays(-$ExclusionPeriod))  {   
			  	
				$i++
				$percentComplete = "{0:N2}" -f (($updatesDeclined/$countSupersededAll) * 100)
				Write-Progress -Activity "Declining Updates" -Status "Declining update #$i/$countSupersededAll - $($update.Id.UpdateId.Guid)" -PercentComplete $percentComplete -CurrentOperation "$($percentComplete)% complete"
                try 
                {
                    $update.Decline()
                    $updatesDeclined++
                }
                catch [System.Exception]
                {
                    Write-Host "Failed to decline update $($update.Id.UpdateId.Guid). Error:" $_.Exception.Message
                }
              }              
            }
        }   
        
    }
    
    Write-Host "  Declined $updatesDeclined updates."
    if ($updatesDeclined -ne 0) {
        Copy-Item -Path $outSupersededList -Destination $outSupersededListBackup -Force
		Write-Host "  Backed up list of superseded updates to $outSupersededListBackup"
    }
    
}
else {
    Write-Host "SkipDecline flag is set to $SkipDecline. Skipped declining updates"
}

Write-Host ""
Write-Host "Done"
Write-Host ""
Pause
.$Lmenu
}
$WSUSCleanUP = { 
<#

    WSUS-CLEANUP-UPDATES
    
    Runs WSUS cleanup task using stored procedures in WSUS database
    thus avoiding timeout errors that may occur when running WSUS Cleanup Wizard.

    The script is intended to run as a scheduled task on WSUS server
    but can also be used remotely. $SqlServer and $SqlDB variables 
    must be defined before running the script on a server without WSUS.

    Version 4

    Version history:

    4    Added database connection state check before deleting an 
         unused update: the script will now attempt to reestablish
         connection if broken.


#>


##########################
# Configurable parameters

$SqlServer = ""    # SQL server host name; leave empty to use information from local registry
$SqlDB = "SUSDB"   # WSUS database name     
$SkipFileCleanup = $SqlServer -ne ""

$log_source = "WSUS cleanup Task"  # Event log source name
$log_debugMode = $true  # set to false to suppress console output 


##########################


$ErrorActionPreference = "Stop"

# basic logging facility

function log_init{
    if ( -not [System.Diagnostics.EventLog]::SourceExists($log_source) ){
        [System.Diagnostics.EventLog]::CreateEventSource($log_source, "Application")
    }
}
# May need to comment out Write-EventLog if error. 
function log( [string] $msg, [int32] $eventID, [System.Diagnostics.EventLogEntryType] $level ){
    Write-EventLog -LogName Application -Source $log_source -EntryType $level -EventId $eventID -Message $msg 
    if ( $log_debugMode ){
        switch ($level){
            Warning {Write-Host $msg -ForegroundColor Yellow }
            Error { Write-Host $msg -ForegroundColor Red }
            default { Write-Host $msg -ForegroundColor Gray }
        }
    }
}

function dbg( [string] $msg ){
    if ( $log_debugMode ){ 
        log "DBG: $msg"  300 "Information"
    }
}

log_init


#########################


function DeclineExpiredUpdates( $dbconn ){

    log "Declining expired updates" 1 "Information"

    $Command = New-Object System.Data.SQLClient.SQLCommand 
    $Command.Connection = $dbconn 
    $Command.CommandTimeout = 3600
    $Command.CommandText = "EXEC spDeclineExpiredUpdates"
    try{
        $Command.ExecuteNonQuery() | Out-Null
    }
    catch{
        $script:errorCount++
        log "Exception declining expired updates:`n$_" 99 "Error"
    }
}

#########################

function DeclineSupersededUpdates( $dbconn ){

    log "Declining superseded updates" 1 "Information"
    
    $Command = New-Object System.Data.SQLClient.SQLCommand 
    $Command.Connection = $dbconn 
    $Command.CommandTimeout = 1800
    $Command.CommandText = "EXEC spDeclineSupersededUpdates"
    try{
        $Command.ExecuteNonQuery() | Out-Null
    }
    catch{
        $script:errorCount++
        log "Exception declining superseded updates:`n$_" 99 "Error"
    }
}


#######################

function DeleteObsoleteUpdates( $dbconn ){

        Log "Reading obsolete update list." 1 "Information"
        $Command = New-Object System.Data.SQLClient.SQLCommand 
        $Command.Connection = $dbconn 
        $Command.CommandTimeout = 600
        $Command.CommandText = "EXEC spGetObsoleteUpdatesToCleanup" 
        $reader = $Command.ExecuteReader()
        $table = New-Object System.Data.DataTable 
        $table.Load($reader)

        $updatesTotal = $table.Rows.Count
        log "Found $updatesTotal updates that can be deleted." 1 "Information"
        # May need to increase timeout to 1800 if error.
        $updatesProcessed=0
        $Command.CommandTimeout = 300
        foreach( $row in $table.Rows ){
            try{
                if ( $dbconn.State -ne [System.Data.ConnectionState]::Open ){
                    log "Re-opening database connection" 2 "Warning"
                    $dbconn.Open()
                }
                $updatesProcessed++
                log "Deleting update $($row.localUpdateID) ($updatesProcessed of $updatesTotal)" 1 "Information"
                $Command.CommandText = "exec spDeleteUpdate @LocalUpdateID=$($row.localUpdateID)"
                $Command.ExecuteNonQuery() | Out-Null
            }
            catch{
                $errorCount++
                log "Error deleting update $($row.localUpdateID):`n$_" 8 "Warning"
            }
        }
Pause
.$Lmenu
}

###################


function DbConnectionString{

    $WsusSetupKey = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"

    if ( $script:SqlServer -eq "" ){
        $serverInfo = Get-ItemProperty -path $WsusSetupKey -Name "SqlServerName" -ErrorAction SilentlyContinue
        $db = Get-ItemProperty -path $WsusSetupKey -Name "SqlDatabaseName" -ErrorAction SilentlyContinue
        if ( ! $server  ){
            throw "Cannot determine SQL server name" 
        }
        $script:SqlServer = $serverInfo.SqlServerName
        $script:SqlDB = $db.SqlDatabaseName
    }

    if ( $script:SqlServer -match "microsoft##" ){
        return "data source=\\.\pipe\$script:SqlServer\tsql\query;Integrated Security=True;database='$script:SqlDB';Network Library=dbnmpntw"
    }
    else{
        return "server='$script:SqlServer';database='$script:SqlDB';trusted_connection=true;" 
    }

}


##############

function DeleteUnusedContent{

    log "Deleting unneeded content files" 1 "Information"
    
    try{
        Import-Module UpdateServices
        $status = Invoke-WsusServerCleanup -CleanupUnneededContentFiles 
        log "Done deleting unneeded content files: $status" 1 "Information"
    }
    catch{
        $script:errorCount++
        log "Exception deleting unneeded content files:`n$_" 99 "Error"
    }

}


###################

function DeleteInactiveComputers( $DbConn ){

    log "Removing obsolete computers" 1 "Information"
    
    $Command = New-Object System.Data.SQLClient.SQLCommand 
    $Command.Connection = $dbconn 
    $Command.CommandTimeout = 1800
    $Command.CommandText = "EXEC spCleanupObsoleteComputers"
    try{
        $Command.ExecuteNonQuery() | Out-Null
    }
    catch{
        $script:errorCount++
        log "Exception removing obsolete computers:`n$_" 99 "Error"
    }

}

function RestartWsusService{
    log "Stopping IIS.." 1 "Information"
    try{
        Stop-Service W3SVC -Force
        try{
            log "Restarting WSUS service.." 1 "Information"
            Restart-Service WsusService -Force 
        }
        finally{
            log "Starting IIS..." 1 "Information"
            Start-Service W3SVC 
        }
    }
    catch{
        $script:errorCount++
        log "Error restarting WSUS services:`n$_" 99 "Error"        
    }
    Start-Sleep -Seconds 30
}

<#------------------------------------------------
                     MAIN                         
-------------------------------------------------#>


$timeExecStart = Get-Date
$errorCount = 0

try{
    
    $Conn = New-Object System.Data.SQLClient.SQLConnection 
    $Conn.ConnectionString = DbConnectionString
    log "Connecting to database $SqlDB on $SqlServer" 1 "Information"
    $Conn.Open() 
    try{
        DeclineExpiredUpdates $Conn
        DeclineSupersededUpdates $Conn
        DeleteObsoleteUpdates $Conn
        DeleteInactiveComputers $Conn   
        RestartWsusService   
        if ( ! $SkipFileCleanup ) {  
            DeleteUnusedContent 
        }
    }
    finally{
        $Conn.Close() 
    }

}
catch{
    $errorCount++
    log "Unhandled exception:`n$_" 100 "Error"
}

$time_exec = ( Get-Date ) - $timeExecStart
log "Completed script execution with $errorCount error(s)`nExecution time $([math]::Round($time_exec.TotalHours)) hours and $([math]::Round($time_exec.totalMinutes)) minutes." 1 "Information"
}
function do-DBIndex{
sqlcmd -S \\.\pipe\MICROSOFT##WID\tsql\query -i ".\Wsus_DB_Maint.sql"
Pause
.$Lmenu
}
function Get-WsusConfig {
<#
    .SYNOPSIS
       Gets WSUS full Server configuration
    .DESCRIPTION
        Not indedependant of this script.
    #>
$wsus = Get-WsusServer $server -port 8530
$wsusConfig = $wsus.GetConfiguration()
$wsusConfig
Pause
&$Mmenu
}
function Get-WsusSubscript {
<#
    .SYNOPSIS
       Get the current WSUS server subscription configuration.
    .DESCRIPTION
        Not indedependant of this script.
    #>
$wsus = Get-WsusServer $server -port 8530
$wsusSub = $wsus.GetSubscription()
$wsusSub
Pause
&$Mmenu
}
function set-DisableSync {
<#
    .SYNOPSIS
       Set the current WSUS server subscription autosync to off.
    .DESCRIPTION
        Not indedependant of this script.
    #>
$wsus = Get-WsusServer $server -port 8530
$wsusSub = $wsus.GetSubscription()
$autosyc = $wsusSub.SynchronizeAutomatically=0
$autosyc
$wsusSub.Save()
$checksub = $wsus.GetSubscription().SynchronizeAutomatically
Write-Host ""
Write-Host "Server subscription SynchronizeAutomatically is now set to $checksub"
Write-Host ""
Pause
.$Lmenu
}
function set-EnbleSync {
<#
    .SYNOPSIS
       Set the current WSUS server subscription autosync to on.
    .DESCRIPTION
        Not indedependant of this script.
    #>
$wsus = Get-WsusServer $server -port 8530
$wsusSub = $wsus.GetSubscription()
$autosyc = $wsusSub.SynchronizeAutomatically=1
$autosyc
$wsusSub.Save()
$checksub = $wsus.GetSubscription().SynchronizeAutomatically
Write-host "Server subscription SynchronizeAutomatically is now set to $checksub"
Pause
.$Lmenu
}
#===============================================================================#
$Smenu = {
    clear
    Write-Host "===================================================================="
    Write-Host "=============== This is the WSUS sustainment program.==============="
    Write-Host "===============        Lets Keep'er goen!            ==============="
    Write-Host "===================================================================="
    Write-Host ""
    Write-Host ""
    Write-Host "************** A few things to note before you begin. *************"
    Write-Host "===================================================================="
    Write-Host ""
    Write-Host "A. This program is ment to be run locally on the server." 
    write-Host "   Some of the functions do work remotly."
    Write-Host "B. Fully test this in a lab enviroment before running on prodiction."
    Write-Host "C. Remeber to Snapshot and Backup in a virtual environment."
    Write-Host "D. This was developed using WID and not a FUll MSSQL DB."
    Write-Host "E. SQLCMD is needed for Maintance of DB."
    Write-Host "F. Remember to work from the bottom of your WSUS Hierarchy ."
    Write-Host ""
    Write-Host "==================================================================="
    Write-Host "Enter the hostname or IP of the remote server you wish to work on."
    Write-Host "Enter " -nonewline 
    Write-host "127.0.0.1 " -foregroundcolor green -nonewline 
    Write-host "or " -nonewline
    Write-host "localhost" -foregroundcolor green
    Write-Host "==================================================================="
    Write-Host ""
    $server =  Read-Host "Name/IP"
# Check if server name provided is correct
    If ($server -ne $Env:Computername) { 
        If (!(Test-Connection -comp $server -count 1 -quiet)) { 
        Write-Warning -Message "$server is not accessible, please check Name/IP or verify netowrk connectivity."
        Write-Host "================================================================================================="
        Break
        } 
    }
$Mmenu = {
    clear
    Write-Host "Please choose fromthe following:"
    Write-Host "========================================="
    Write-Host "1. Server information"
    Write-Host "2. Maintenace operations"
    Write-Host "========================================="
    Write-Host " To cancel, enter C " -foregroundcolor red
    Write-Host "========================================="
    $ans1 = Read-host "Choice"
    if ($ans1 -eq 1) { 
        # Get Information 
        clear
        Write-Host "1. Current WSUS Subscription configuration"
        Write-Host "2. Current full WSUS configuration"
        Write-Host "3. Change Server"
        Write-Host "4. Main Menu"
        Write-Host "========================================="
        Write-Host " To cancel, enter C " -foregroundcolor red
        Write-Host "========================================="
        $ans2 = Read-host "Choice"
        if ($ans2 -eq 1) {
            Get-WsusSubscript
        } elseif ($ans2 -eq 2) {
            Get-WsusConfig
        } elseif ($ans2 -eq 3) {
        .$Smenu
        } elseif ($ans2 -eq 4) {
        .$Mmenu
        } else {
            Write-Host "Canceling operation..."
            exit
            }
            
} elseif ($ans1 -eq 2) {
# Do Maintenance
    $Lmenu = {
        clear
        Write-Host "**** This is the  Maintenance section. ****"
        Write-host ""
        Write-host "You should create a backup of the Database before you begin."
        Write-Host "==============================================================="
        Write-host ""
        Write-Host "Please select from the following:"
        Write-Host "========================================="
        Write-Host "  Options 2, 5, & 7 can be run remotely "
        Write-host "========================================="
        Write-Host "1. Create Backup of DB"
        Write-Host "2. Disable the syncronization schedule"
        Write-Host "3. Create Custom DB Indexes (One time event)" 
        Write-Host "4. Re-index the WSUS database"
        Write-Host "5. Decline superseded updates"
        Write-Host "6. Run the WSUS Server Cleanup [beta] Better to use the wizard for now." 
        Write-Host "7. Enable the syncronization schedule"
        Write-Host "8. New server"
        Write-Host "9. Main Menu"
        Write-Host "========================================="
        Write-Host " To cancel, enter C " -foregroundcolor red
        Write-Host "========================================="
        $opt = Read-Host "Answer"
        clear
        if ($opt -eq '1') {Do-backup
        }elseif ($opt -eq '2') {set-DisableSync

        }elseif ($opt -eq '3') {Write-Host "Creating custom WSUS indexes"
            Write-Host "-------------------------------------------------------------"
            Write-Host "This needs to be run localy on the WSUS server."
            Write-Host "This is proceedure requires the SQLCMD to be installed."
            write-host "Search for the Download."
            Write-Host "Make sure you have the Wsus_custom_indexing.sql script."
            Write-Host ""
            Write-Host "NOTE: If you get an error massage for 'nclLocalizedPropertyID'"
            write-host "      already exists. This step has been done."
            Write-Host "--------------------------------------------------------------"
            Write-Host ""
            $conf = Read-Host "Are you ready to proceed (y/n)?"
            if ($conf -eq 'y') {Do-CustomIndex}
            else {Write-Host "Canceling operation..."
            exit}
            
        }elseif ($opt -eq '4') {Write-Host "Re-indexing Database"
         do-DBIndex                  
        }elseif ($opt -eq '5'){
            Write-Host "NOTE: Last Level Updates are not declined;"
            Write-Host "are Superceeded; do not have superceded updates."
            Write-Host "update_a.2.1<--- First Level"
            Write-Host "update_a.2 "
            Write-Host "update_a.1"
            Write-Host "update_a <--- Last Level"
            Write-Host "==================================================="
            Write-Host "==================================================="
            Write-Host "How would you like to proceed?"
            Write-Host "==================================================="
            Write-Host "1. Test Run and SkipDecline"
            Write-Host "2. Run Decline now"
            Write-Host "3. Run Decline now with an ExclusionPeriod"
            Write-Host "4. Run Decline Now on Last Level Updates"
            $decl = Read-Host "Answer"
            if ($decl -eq '1') {Do-DeclineSuper -SkipDecline}
            if ($decl -eq '2') {Do-DeclineSuper}
            if ($decl -eq '3') {
            $days = Read-Host "Exclusion Period Days:"
            Do-DeclineSuper -ExclusionPeriod $days
            }if ($decl -eq '4') {Do-DeclineSuper -DeclineLastLevelOnly}
             
        }elseif ($opt -eq '6'){Write-Host "Running the WSUS Server Cleanup"
              .$WSUSCleanUP 
        }elseif ($opt -eq '7') {set-EnbleSync
        }elseif ($opt -eq '8') {.$Smenu
        }elseif ($opt -eq '9') {.$Mmenu
        }else {clear
              Write-Host "Operation Canceled"
              Write-host ""
              exit
              }
}}
.$Lmenu}
.$Mmenu}
.$Smenu
# NOTE Fix mkdir
