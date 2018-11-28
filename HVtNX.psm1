##################################################################################
#   Copyright [2018] [Pekka Halmkrona]                                           #
#                                                                                #
#   Licensed under the Apache License, Version 2.0 (the "License");              #
#   you may not use this file except in compliance with the License.             #
#   You may obtain a copy of the License at                                      #
#                                                                                #
#       http://www.apache.org/licenses/LICENSE-2.0                               #
#                                                                                #
#   Unless required by applicable law or agreed to in writing, software          #
#   distributed under the License is distributed on an "AS IS" BASIS,            #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
#   See the License for the specific language governing permissions and          #
#   limitations under the License.                                               #
##################################################################################


$Scriptversion = "0.0.11 @ Nextconf"
$ScriptVersionDate = "28.11.2018"


Write-Host "######################################################################################" 
Write-Host "###              Script version $Scriptversion, date $ScriptVersionDate                            ###"
Write-Host "######################################################################################"


$LoadedSnapins = Get-PSSnapin -Name NutanixCmdletsPSSnapin -ErrorAction SilentlyContinue
if (-not $LoadedSnapins) {   

    Try{
        Add-PsSnapin NutanixCmdletsPSSnapin -ErrorAction Stop
        }
    Catch{
        Write-Host "Nutanix PSSnapin could not be loaded"
        Write-Host "Have you clikked the Nutanix CMDlet incon in Startmenu"
    }
}

Function script:New-HVtNXVM {
Param(
   [Parameter(Mandatory=$True,Position=1)][Microsoft.HyperV.PowerShell.VirtualMachineBase]$VM,
   [Parameter(Mandatory=$True,Position=2)][String]$Logfile
)
   
    
   "#######################################" | Out-File -Append -FilePath $VMlog
   "$($vm.Name): Trying to create VM"  | Out-File -Append -FilePath $VMlog
   
    Open-HVtNXConnection 

    #$VMVlans = $VM |Get-VMNetworkAdapterVlan
    $vmnics = $VM.NetworkAdapters
    $VMProcessor = $VM | Get-VMProcessor
    $VMMem = $VM | Get-VMMemory
    $Error.Clear()
    Try {
        If ($vm.DynamicMemoryEnabled){
        
            Write-host "Script found that you have dynamic memory enabled in vm: " $vm.vmname.ToUpper() " Nutanix does not support dynamic memory."
            [int]$Memory = Read-Host -Prompt "How much in MB you would like to assign memory"
            New-NTNXVirtualMachine -Name $VM.Name -NumVcpus $VMProcessor.Count -MemoryMB $Memory 
        }
        else {
            New-NTNXVirtualMachine -Name $VM.Name -NumVcpus $VMProcessor.Count -MemoryMB ($VMMem.Startup / 1MB)
        }
  
   

    }
    Catch{
    Write-Host "Something happened when creating vm. Errors are here:" 
    $Error
    $Error  | Out-File -Append -FilePath $VMlog

       
    }
    Finally{
    If(!$Error){
        Write-Host "Successfully created VM $($vm.vmname)"
        "$($vm.vmname): Successfully created VM" | Out-File -Append -FilePath $VMlog
        }

    $Error.Clear()
    }


   
    
    # Waiting for VM to be created, after creation it will be read in to $NXvminfo
    $loopcount = 0
    $NXvminfo = ""
    While ((-not $NXvminfo) -and $loopcount -lt 10 ){
        Sleep -Seconds 1
        $NXvminfo = Get-NTNXVM | where {$_.vmName -eq $VM.Name}
        $loopcount += 1
        #$loopcount
        #$NXvminfo
    }

    #Notify user if there is problem with reading 
    if (-not $NXvminfo){
        Write-Host "Could not read VM information from Nutanix, it should already be there. WM name is: "$VM.VMName
        Write-Host "Script will now exit!!!"

       # exit
    
    }
    
     # Reading settings from Notes
    $script:Notes = $vm.Notes.Trim()
    $hwclock = $null
    $CloneMAC = $null
    $hwclock = ($Notes -Split('[\r\n]')| Where {$_ -like "HVToNutaUseCurrentTimeZoneHwClock" })
    $CloneMAC = ($Notes -Split('[\r\n]')| Where {$_ -like "HVToNutaCloneMAc" })


        If ($hwclock){
             
             Set-NTNXVirtualMachine -Vmid $NXvminfo.uuid -Timezone ((Get-NTNXCluster).timezone)

         }

    "$($vm.Name): Trying to add Nics"  | Out-File -Append -FilePath $VMlog
    foreach ($vmnic in  $vmnics){
        Try {
            $NXVMNet = Get-NTNXNetwork |Where {$_.vlanid -eq $vmnic.VlanSetting.AccessVlanId}
            $NXnic = New-NTNXObject -Name VMNicSpecDTO
            $NXnic.networkUuid = $NXVMNet.uuid
            If ($CloneMAC){
                $NXnic.macAddress = ($vmnic.MacAddress  -replace '(..)','$1:').trim(':')
            }
 
            # Adding a Nic
            Add-NTNXVMNic -Vmid $NXvminfo.uuid -SpecList $NXnic
            }
        Catch{

            Write-Host "Something happened when adding NICs on $($vm.vmname) with vlan id $($vmnic.VlanSetting.AccessVlanId) . Errors are here:" 
            $Error
            $Error  | Out-File -Append -FilePath $VMlog
     
        }
        Finally{
            If(!$Error){
            Write-Host "Successfully added NIC $($vm.vmname)"
            "$($vm.vmname): Successfully added NIC with vlan id: $($vmnic.VlanSetting.AccessVlanId)" | Out-File -Append -FilePath $VMlog
    
        }

        $Error.Clear()
     
     
        }


    
     }
   
   
    # Add CDROM do guest tools are easier to install
    $vmDisk = New-NTNXObject -Name VMDiskDTO
   
    $vmDisk.isCdrom = $True
    $vmDisk.isEmpty = $True
  
    # Adding the CDROM to the VM
    Add-NTNXVMDisk -Vmid $NXvminfo.uuid -Disks $vmDisk

}


Function local:Open-HVtNXConnection {

   $result = ""
   $result = Get-NTNXCluster -ErrorAction SilentlyContinue
   If (-not $result){

         Connect-NutanixCluster -Server $NTNXServer -UserName $NTNXUser -Password $securestr -AcceptInvalidSSLCerts -ForcedConnection  
    }

}






Function script:Get-HVtNXJobNameParser {
Param(
    [Parameter(Mandatory=$True,Position=1)] [String]$Name


)
        
        $ImportConf = New-Object -TypeName PSObject
        $ImportConf | Add-Member -NotePropertyName "BatchName" -NotePropertyValue $Name.Split(";")[1] 
        $ImportConf | Add-Member -NotePropertyName "VMName" -NotePropertyValue $Name.Split(";")[2] 
        $ImportConf | Add-Member -NotePropertyName "DiskPath" -NotePropertyValue $Name.Split(";")[3] 
        $ImportConf | Add-Member -NotePropertyName "DiskAddress" -NotePropertyValue $Name.Split(";")[4] 
        $ImportConf | Add-Member -NotePropertyName "Container" -NotePropertyValue $Name.Split(";")[5] 
            
return $ImportConf


}



# Function will import disk to nutanix VM
Function script:Import-HVtNXDisk{
Param (
 [Parameter(Mandatory=$True,Position=1)][String]$Logfile,
 [Parameter(Mandatory=$True,Position=1)][String]$BatchName

)




    If (Get-job  |Where {$_.State -eq "Failed" -and $_.Name -like "NuTa;$BatchName;*"}){ 
        $FailedJobs = Get-job  |Where {$_.State -eq "Failed" -and $_.Name -like "NuTa;$BatchName;*"}
        "##################################### JOB ERROR ######################################################" | Out-File -Append -FilePath $LogFile
        $FailedJobs |Receive-job -Keep| Out-File -Append -FilePath $LogFile
        "################################## END OF JOB ERROR ##################################################" | Out-File -Append -FilePath $LogFile
        $FailedJobs | Remove-Job
    }

    # All the necressary settings are stored in the powershell job name. 
    # Job name contains VM name, ADSF, Disk bus and number
    $JobsCompleted = Get-job  |Where {$_.State -eq "Completed" -and $_.Name -like "NuTa;$BatchName;*"}
           
    foreach ($JobCompleted in $JobsCompleted){
           
        
        Open-HVtNXConnection
        $ImportConf = Get-HVtNXJobNameParser -Name $JobCompleted.Name
        $datestring = Get-Date -Format yyyyMMddHHMMss
        "Job: $($JobsCompleted.Name) comleted at $datestring" | Out-File -Append -FilePath $LogFile       
        $Error.Clear()        
        Try{           
            ## Disk Creation
            $diskCloneSpec = New-NTNXObject -Name VMDiskSpecCloneDTO
            $diskCloneSpec.ndfs_filepath = $ImportConf.DiskPath  # ADSF path
            $vmDisk = New-NTNXObject -Name VMDiskDTO
            $vmDiskAddress = New-NTNXObject -Name VMDiskAddressDTO
            $vmDiskAddress.deviceBus = $ImportConf.DiskAddress.Split(".")[0]   # Can be ide or scsi
            $vmDiskAddress.deviceIndex = $ImportConf.DiskAddress.Split(".")[1] # ID of the disk 0 to onwards
            $vmDisk.vmDiskClone = $diskCloneSpec
            $vmDisk.diskAddress = $vmDiskAddress
  
            # Adding the Disk to the VM
            Add-NTNXVMDisk -Vmid (Get-NTNXVM | Where {$_.vmname -eq $ImportConf.VMName}) -Disks $vmDisk
            }
            Catch{
                Write-Host "Could not import disk. Error is here:"
                $Error
                $Error | Out-File -Append -FilePath $LogFile
            
            }
            Finally{
                If(!$Error){
                   $datestring = Get-Date -Format yyyyMMddHHMMss
                   "Succesfully imported disk $($ImportConf.DiskPath) to VM $($ImportConf.VMName) at $datestring" | Out-File -Append -FilePath $LogFile
                   $Error.Clear()
                }
            
            
            }
            
             
               
        # Removeing Job, so we don't need to do this again
       
        Remove-Job -Job $JobCompleted 
           
           
    }


}

# This function will print status information of the transfer process
Function script:Show-HVtNXMoveStatus {
    Clear
    $VMSpecs = @()
    $JobsRunning = Get-job  |Where {$_.State -eq "Running" -and $_.Name -like "NuTa;*"}
    If ($JobsRunning){
        foreach($job in $JobsRunning){
            $jobsparams = Get-HVtNXJobNameParser -Name $job.Name
            $result = $job | Receive-Job -Keep | select -Last 1
            if(-not $result){
                $result = " "      
            }
        
            $VMinfo = New-Object System.Object

                $vminfo | Add-Member -type NoteProperty -name Name -Value $jobsparams.Vmname
                $vminfo | Add-Member -type NoteProperty -name Percent -Value $result.Trim()
                $vminfo | Add-Member -type NoteProperty -name Diskpath -Value $jobsparams.DiskPath
                $vminfo | Add-Member -type NoteProperty -name Host -Value $job.location
                
        
            $VMSpecs += $VMinfo
            
        }
        $VMSpecs |Format-Table -AutoSize -Wrap
        #write-host ($job | Receive-Job -Keep)
    }
    Else {
        Write-host "Waiting jobs to be created"
    
    }
}

# This function will parse disk information from text string which is stored in Hyper-V notes field
Function script:Get-HVtNXDiskNameParser{
Param(
 [Parameter(Mandatory=$True,Position=1)] [String]$String


)

     $RawDArray = $String.Split(";")

     If (($RawDArray[1].Split(".")|Select-Object -Last 1) -eq "vhd"){ $VHDType = "vpc"  }
     Else { $VHDType = "vhdx" }

     $Diskparams = New-Object System.Object
     $Diskparams| Add-Member -type NoteProperty -name DiskString -Value  ($RawDArray[1].Split("\") |Select-Object -Last 1) # Disk filename with orginal extension
     $Diskparams| Add-Member -type NoteProperty -name VHDType -Value  $VHDType # Qemu-img type of the vhd vhx or vpc
     $Diskparams| Add-Member -type NoteProperty -name Container -Value ($RawDArray[3]) # Container name
     $Diskparams| Add-Member -type NoteProperty -name BusID -Value ($RawDArray[2]) # Bus id like: scsi.0
     $Diskparams| Add-Member -type NoteProperty -name ADSFPath -Value ($RawDArray[1].replace(":","").replace(($RawDArray[1].Split(".")|Select-Object -Last 1),"raw").Replace("\","/"))#.ToLower() # Full ADSF pat with filename and extension
     $Diskparams| Add-Member -type NoteProperty -name HVFilePath -Value $RawDArray[1]#.ToLower()

     Return $Diskparams

}



Function global:Move-HVtNX{
Param(
   [Parameter(Mandatory=$True,Position=1)] [string]$HyperVCluster, 
   [Parameter(Mandatory=$True,Position=2)] [String]$BatchName,
   [Parameter(Mandatory=$True,Position=3)] [DateTime]$StartTime,
   [Parameter(Mandatory=$True)] [string]$NXServer ,
   [Parameter(Mandatory=$True)] [string]$NXUser,
   [Parameter(Mandatory=$True)] [securestring]$NXPassword,
   [Parameter(Mandatory=$True)] [String]$UncPathToQemuShare,
   [Parameter(Mandatory=$True)] [String]$QemuDrive,
   [Parameter(Mandatory=$True)] [Int]$SimultaneusCount,
   [Parameter(Mandatory=$True)] [Int]$Streams,
   [Parameter(Mandatory=$True)] [string]$LogFolder

 
)



# Define variables

    $global:NTNXServer = $NXServer
    $global:NTNXUser = $NXUser
    $global:securestr = $NXPassword 
    $NTNXPassword = ""
    $JobBatchName = "Nuta;" + $BatchName + ";"   
    $FullBatchName = "HVToNutaBatch;" + $BatchName
    $datestring = Get-Date -Format yyyyMMddHHMMss
    $VMlog = $LogFolder + "\" + $BatchName + "_VM_" + $datestring + ".txt"
    $VMDiskLog = $LogFolder + "\" + $BatchName + "_Disk_" + $datestring + ".txt"

# End of defining variables
    
    # Read Hyper-V cluster details and read every VM:s Notes field
    $clusterresources = Get-ClusterResource -Cluster $HyperVCluster |Where {$_.ResourceType -eq "Virtual Machine" }
    $vms=  @()
    For($i=0;$i -lt $clusterresources.Count; $i++){
    
        Write-Progress -Activity "Finding VM:s to migrate" -status "Reading VM no. $i" -percentComplete ($i / $clusterresources.Count *100) -CurrentOperation ("Already found VMs: " + $vms.count)
        # If vm has "Batch name" in it's notes field, it will be included in the array
        $vms += $clusterresources[$i]| Get-VM | Where { ($_.Notes -Split('[\r\n]')) -Contains $FullBatchName }
    
    }
    Write-Progress -Activity  "Finding VM:s to migrate" -Status "Ready" -Completed

    
    Clear
    Write-Host "Following VMs will be migrated:"
    $vms.Name

    $Confirmation = Read-Host -Prompt "If this list is correct write: Yes"
    If ($Confirmation.ToLower() -ne "yes"){
        Write-Host "No confirmation, so script will exit. Press CTRL + c if you don't want to close powerShell console"
        pause
      #  Exit

    }

    
    Open-HVtNXConnection 
    Clear
    Write-Host "Now script will check if there is alreay VM:s with same name in Nutanix cluster which has any disks"
    foreach ($vm in $vms){
        if (Get-NTNXVM | Where {$_.vmname -eq $vm.vmname}){
            Write-Host "Found VM with name " $vm.VMName
            $NTVM = Get-NTNXVM | Where {$_.vmname -eq $vm.vmname} 
            $NTDisks = Get-NTNXVMDisk -Vmid $NTVM.uuid |Where {$_.isCdrom -eq $false}
            If ($NTDisks.count -gt 0){
                Write-Host "Found VM with name " $vm.VMName " And it has " $NTDisks.count " Disks. Script does not know what to do, so it will exit now"
                
                $NTDisks
                Write-host "Press CTRL + c if you don't want to close powerShell console"
                Pause

              #  Exit
        
            }
    
        }
    


    }

    Clear
    Write-host "It seems that there wasn't any VM:s with same name that hyper-v and which already has a disk attach to it"
    Write-host "Next script will make all VM which are not yet in Nutanix cluster."
    $Confirmation = Read-Host -Prompt "Would you like to make VMs in Nutanix? Write yes if so." 
    If ($Confirmation.ToLower() -ne "yes"){
        Write-Host "No confirmation, so script will exit, press CTRL + c if you don't want to close powerShell console"

#        Exit

    }


    Open-HVtNXConnection

    foreach ($vm in $vms){
        if (!(Get-NTNXVM | Where {$_.vmname -eq $vm.vmname} )){
            New-HVtNXVM -VM $vm -logfile $VMlog
        }
        "#######################################" | Out-File -Append -FilePath $VMlog
        "$($vm.Name) Already exist in Nutanix  "  | Out-File -Append -FilePath $VMlog

    }

    Clear

    # This is really quick version of delay scripot wich will loop until time is reached
    While ((Get-Date) -lt $StartTime){
        clear
        $TimeToStart = $Starttime - (Get-Date) | Select Hours,Minutes,seconds 
        Write-host "Migration will begin at " $TimeToStart.Hours":"$TimeToStart.Minutes":"$TimeToStart.Seconds
        sleep -Seconds 1


    }


    # This part will initiate actual transfer process
    foreach($VM in $vms){
        $VMDisksToMove = $VM.Notes -Split('[\r\n]') |Where {$_ -like "HVToNutaDisk*" -and $_ -notlike "*;none"}
    
        If ( $VM.state -ne "Off" ){
            Write-Host "Shutting down vm: " $vm.VMname 
            $VM | Stop-VM -Confirm:$False -Force
       
            
        }
        Write-Host "Starting to migrate server:" $VM.VMName
        foreach ($DiskToMove in $VMDisksToMove){
                  
            $DiskProperties = New-Object System.Object
            $DiskProperties = Get-HVtNXDiskNameParser -String $DiskToMove
            
            # Windows UNC path, where RAW disk image will be stored
            $WinRAWFilePath = "\\" + $NTNXServer + "\" + $DiskProperties.Container + "\" + $HyperVCluster +"\" + $DiskProperties.ADSFPath.Replace("/","\").Replace("\\","") # Full raw file path to qemu destination 
            
            # Explanation of command
            # First we need to map drive where qemu is. In this case it's ADSF path. This is done because windows version of qemu needs at least as much storage space in current drive as vhd size is.
            # Qemudrive is just drive letter for qemu, you can choose any available drive.
            # YOU MUST BE SURE THAT THIS DRIVE LETTER IS NOT USED IN ANY OTHER USE
            # Then we just give parameters to qemu-img 
            "$($vm.Name) Trying to disk move job for disk: $($DiskProperties.HVFilePath)  "  | Out-File -Append -FilePath $VMDiskLog
            $Error.Clear()
            Try {
                # Generating command(s), split by ";". First it will map drive and after that it will run qemu-img, with necessary parameters
                $CMDString =  'net use '+$QemuDrive+' "'+ $UncPathToQemuShare +'";'+$QemuDrive  +';& "'+$QemuDrive+'\qemu-img\qemu-img.exe" convert -m '+ $Streams + ' -p -f ' + $DiskProperties.VHDType  + ' -O raw "' + $DiskProperties.HVFilePath + '" "' + $WinRAWFilePath + '"'
                write-host $CMDString
                pause
                $scriptBlock = [Scriptblock]::Create($CMDString)
                
                "Job Command# $CMDString" | Out-File -Append -FilePath $VMDiskLog
               
                # Script will run command remotely on that host which own Hyper-V virtual machine
                $JobNameString = "NuTa;" + $BatchName + ";" + $vm.VMName + ";/" + $DiskProperties.Container  + "/" + $HyperVCluster + "/"+ $DiskProperties.ADSFPath.Replace("//","") + ";" + $DiskProperties.BusID + ";" + $DiskProperties.Container
                "Job String# $JobNameString" | Out-File -Append -FilePath $VMDiskLog
                
                Invoke-Command -ComputerName $vm.ComputerName -Command  $scriptBlock -AsJob -JobName $JobNameString
                }
            Catch{
                Write-Host "Could not create disk move job. Error is here:"

                $Error | Out-File -Append -FilePath $VMDiskLog
            
            }
            Finally{
                If(!$Error){
                   $datestring = Get-Date -Format yyyyMMddHHMMss
                   "Succesfylly created disk move job for disk $($DiskProperties.HVFilePath) at $datestring" | Out-File -Append -FilePath $VMDiskLog
                
                }
            
            
            }
 
            [array]$JobsRunning = Get-job  |Where {$_.State -eq "Running" -and $_.Name -like "$JobBatchName*"}
            $SimRunCount =  $JobsRunning.count
            
            # When script parameter Simultaneuscount is lower than current count if disk moves, it will initiate new move
            While ($SimRunCount -ge $SimultaneusCount ){
               # $SimRunCount = Get-NutaSimRunCount
               Sleep -Seconds 15

               [array]$JobsRunning = Get-job  |Where {$_.State -eq "Running" -and $_.Name -like "$JobBatchName*"}
               $SimRunCount =  $JobsRunning.count

               Import-HVtNXDisk -Logfile $VMDiskLog -BatchName $BatchName
               Show-HVtNXMoveStatus

            } # End of looping While simruncount
    
    
        } # End of ForEach Disks
  


    } # End of ForEach VM
    clear

    Write-Host "All disk are now on their way to Nutanix"
    # All disk should be on their way to notanux, so it will just wait for them and it will show status

    While (Get-job  |Where {$_.Name -like "$JobBatchName*"}){

        Show-HVtNXMoveStatus
        Import-HVtNXDisk -Logfile $VMDiskLog -BatchName $BatchName
        Sleep -Seconds 15



    }




}


<# 
 .Synopsis
  Graphical UI to prepare Hyper-V Cluster VMs to convert and import them to Nutanix AHV

 .Description
  Graphical UI will help to prepare disk configuration before migrating them to Nutanix AHV. 
  
 .Parameter ClusterName
  Name of the Hyper-V Cluster. Be sure that it could be accessed by remote powershell commands and eith RPC.

 .Parameter ADSFContainers
  Array of the Nutanix Storage Containers.

 .Example
   # Show a default display of this month.
   Open-HVtNXConfigForm -$ClusterName HYPERVCLUSTERNAME -$ADSFContainers "Cont1","Cont2","Cont3","Cont4"
#>
function global:Open-HVtNXConfigForm { 
Param(

    [Parameter(Mandatory=$True,Position=1)][String]$ClusterName,
    [Parameter(Mandatory=$True,Position=1)][Array]$ADSFContainers

) 

    $clusterresources = Get-ClusterResource -Cluster $ClusterName |Where {$_.ResourceType -eq "Virtual Machine" }
    $vms=  @()
    For($i=0;$i -lt $clusterresources.Count; $i++){
    
        Write-Progress -Activity "Finding VM:s to migrate" -status "Reading VM no. $i" -percentComplete ($i / $clusterresources.Count *100) 
        $vms += $clusterresources[$i]| Get-VM 
    
    }
    Write-Progress -Activity  "Finding VM:s to migrate" -Status "Ready" -Completed


   
    $ADSF_selection = New-Object System.Data.DataTable
    [void]$ADSF_selection.Columns.Add("NXContainer")
    foreach($container in $ADSFContainers) {$ADSF_selection.Rows.Add($container)}

    #Disks with "none" as a container name, will be skipped, but it will be added if it's not listed
    if($ADSF_selection.NXContainer -notcontains "None"){$ADSF_selection.Rows.Add("none")}



    #region Import the Assemblies 
    Write-Debug "Loading Assemblies" 
    [reflection.assembly]::loadwithpartialname("System.Drawing") | Out-Null 
    [reflection.assembly]::loadwithpartialname("System.Windows.Forms") | Out-Null 
    #endregion 

    #Variables
    $NXSCSINos  = New-Object System.Data.DataTable

    [void]$NXSCSINos.Columns.Add("NXSCSINo") # All variable tyopes must be defined before it can be used in form, values will be filled in code
    # End of variables

    # Region Form Objects (not a form, but objects)
    $Main1 = New-Object System.Windows.Forms.Form 
    $btnQuit = New-Object System.Windows.Forms.Button 
    $btnSave = New-Object System.Windows.Forms.Button 
    $btnLoad = New-Object System.Windows.Forms.Button
    $dataGridView = New-Object System.Windows.Forms.DataGridView 
    $ServerName = New-Object system.Windows.Forms.ComboBox
    $BatchName = New-Object System.Windows.Forms.TextBox 
    $BatchLabel= New-Object system.Windows.Forms.Label
    $ServerLabel = New-Object system.Windows.Forms.Label
    $labelCheckp = New-Object system.Windows.Forms.Label
    $MACCheck = New-Object System.Windows.Forms.Checkbox
    $MACLabel  = New-Object system.Windows.Forms.Label
    $hwTimeZoneCheck = New-Object System.Windows.Forms.Checkbox
    $hwTimezoneLabel  = New-Object system.Windows.Forms.Label
    # End # Region Form Objects

    # ----------------------------
    # FORM EVENT SCRIPT BLOCKS
    # ----------------------------

    $GetServerData={
    
        $script:VMDisks = New-Object System.Data.DataTable
        [void]$VMDisks.Columns.Add("VMName")
        [void]$VMDisks.Columns.Add("Type")
        [void]$VMDisks.Columns.Add("DriveParams")
        [void]$VMDisks.Columns.Add("Path")
        [void]$VMDisks.Columns.Add("NXSCSINo")
        [void]$VMDisks.Columns.Add("NXContainer")
        #clearing the table 
        $dataGridView.DataSource=$Null 


    
        $vm = $VMs | Where {$ServerName.SelectedItem -eq $_.VMName}

       # $vm |select *  |Out-GridView

        $script:Notes = $vm.Notes.Trim()

      
        #Get Batchname from notes, if it exist. 
        $BatchString = ($Notes -Split('[\r\n]')| Where {$_ -like "HVToNutaBatch*" })
        If ($BatchString){
         $BatchName.Text  = $BatchString.split(";")[1]

         }
         Else {$BatchName.Text = "" }

         # Get hwclock setting from Notes
         $hwclock = " "
         $hwclock = ($Notes -Split('[\r\n]')| Where {$_ -like "HVToNutaUseCurrentTimeZoneHwClock" })
        If ($hwclock){
         $hwTimeZoneCheck.Checked = $True

         }
         Else {$hwTimeZoneCheck.Checked = $False }

         # Get CloneMAC setting from Notes
         $CloneMAC = " "
         $CloneMAC = ($Notes -Split('[\r\n]')| Where {$_ -like "HVToNutaCloneMAc" })
         
            If ($CloneMAC){
             $MACCheck.Checked = $True

             }
             Else {$MACCheck.Checked = $False }


        # UI will not show input boxes, if snapshot is taken
        If($vm|Get-VMSnapshot){
            $btnSave.Visible = $False
            $labelCheckp.Visible = $true
            $BatchName.Visible = $False
            $BatchLabel.Visible = $False
            $MACLabel.Visible = $False
            $MACCheck.Visible = $False
            $hwTimezoneLabel.Visible = $False
            $hwTimeZoneCheck.Visible = $False
    
        }
        Else{
            $btnSave.Visible = $True
            $labelCheckp.Visible = $False
            $BatchName.Visible = $True
            $BatchLabel.Visible = $True
            $MACLabel.Visible = $True
            $MACCheck.Visible = $True
             $hwTimezoneLabel.Visible = $True
            $hwTimeZoneCheck.Visible = $True
        }

        foreach($drive in $vm.HardDrives){
        
            $DriveParams = ""
            $DriveParams += "ContNo:" + $drive.ControllerNumber + " ContLoc:" +$drive.ControllerLocation + " DiskNo" +$drive.DiskNumber
       
            $nx_disk_setting_line = $Notes -Split('[\r\n]')| Where {$_ -like "HVToNutaDisk*" -and $_ -Match $drive.path.Replace("\","\\")}  # Match is regular expression, so it needs double escape \\
            
            If ($nx_disk_setting_line.count -eq 1 ){
                $nx_disk_setting = $nx_disk_setting_line.split(";")
                $NXNo = $nx_disk_setting[2]
                $NXContainer = $nx_disk_setting[3]
            }
            Else {
                $NXNo = ""
                $NXContainer = ""
            
        
        
            }
            
            # If there is container name which is not listed as parameter in this function, then container name will be added to container name list
			if($ADSF_selection.NXContainer -notcontains $NXContainer -and $NXContainer -notlike ""){
				 
				 $ADSF_selection_temp = $ADSF_selection
				 $ADSF_selection_temp.Rows.Add($NXContainer)
				 $CLM_NXContainer.DataSource = $ADSF_selection_temp
			
			
			}
			
			
            $VMDisks.Rows.Add($vm.Name, $drive.ControllerType,$DriveParams, $drive.path, $NXNo, $NXContainer )
    
        }

     $diskcount = 0..($vm.HardDrives.count - 1)
     $NXSCSINos.clear()
     $diskcount |foreach {[void] $NXSCSINos.Rows.Add(("scsi." + $_))}

     $dataGridView.DataSource = $VMDisks

 

    }

    $Quit=  
    { 
      
        $Main1.Close() 
    } #End Quit scriptblock 


    $Save=  
    {
       $Noteslines = New-Object -typeName System.Collections.Arraylist 
       $Noteslines.Clear()

       $vm = $VMs | Where {$ServerName.SelectedItem -eq $_.VMName}
   

       [array]$NotesArr = $vm.Notes -Split('[\r\n]')| Where {$_ -notlike "HVToNuta*" -and $_ -notlike '[\n]' -and $_ -notlike '[\r]'} |foreach{$_ -replace("`r","")  }
   
      # $Noteslines = {$NotesArr}.Invoke()
       foreach($noteline in $NotesArr){
            If ($noteline.Length -ne 0){
              # Write-Host $noteline
               $Noteslines.Add($noteline)
            }
       }
   
       ForEach ($vmdisk in $VMDisks){
            If ($vmdisk.NXSCSINo -and $vmdisk.NXContainer){
                $Noteslines.add( "HVToNutaDisk;" + $vmdisk.Path + ";" +  $vmdisk.NXSCSINo + ";" +  $vmdisk.NXContainer)
                }
       }
  

       If ($BatchName.Text) {
            $Noteslines.Add( "HVToNutaBatch;" + $BatchName.Text ) 
   
       }
        If ($MACCheck.Checked  -eq $true) {
            $Noteslines.Add( "HVToNutaCloneMAc" ) 
   
       }
     
      
         If ($hwTimeZoneCheck.Checked -eq $true) {
            $Noteslines.Add( "HVToNutaUseCurrentTimeZoneHwClock" ) 
   
       }
      

       [string]$NewNote = ""
       foreach($Noteline in $Noteslines) {
        $NewNote += $Noteline + "`n"
       }
    

       #$vm = $VMs | Where {$ServerName.SelectedItem -eq $_.VMName}
       #$NewNote | Out-GridView
       $vm | Set-VM -Notes $NewNote 

      $GetServerData.Invoke()
    } #End Save scriptblock 

    # ----------------------------
    # END FORM EVENT SCRIPT BLOCKS
    # ----------------------------

    # ----------------------------
    # Defining the form itself
    # ----------------------------

    $Main1.Name = "Main1"
    $Main1.Text = "HVtNX Config Form"
    $Main1.DataBindings.DefaultDataSourceUpdateMode = 0
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 890 
    $System_Drawing_Size.Height = 359 
    $Main1.ClientSize = $System_Drawing_Size 
    $Main1.StartPosition = 1 
    ### Button GetServerData

    $btnLoad.UseVisualStyleBackColor = $True 
    $btnLoad.Text = 'LoadVMDisk' 
 
    $btnLoad.DataBindings.DefaultDataSourceUpdateMode = 0 
    $btnLoad.TabIndex = 1 
    $btnLoad.Name = 'GetServerData' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 75 
    $System_Drawing_Size.Height = 23 
    $btnLoad.Size = $System_Drawing_Size 
    #$btnGo.Anchor = 9 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 233 
    $System_Drawing_Point.Y = 31 
    $btnLoad.Location = $System_Drawing_Point 
    $btnLoad.add_Click($GetServerData) 
 
    $Main1.Controls.Add($btnLoad) 
    ### End Button GetServerData

    ### Button Quit
    $btnQuit.UseVisualStyleBackColor = $True 
    $btnQuit.Text = 'Close' 
 
    $btnQuit.DataBindings.DefaultDataSourceUpdateMode = 0 
    $btnQuit.TabIndex = 2 
    $btnQuit.Name = 'btnQuit' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 75 
    $System_Drawing_Size.Height = 23 
    $btnQuit.Size = $System_Drawing_Size 
    #$btnQuit.Anchor = 9 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 341 
    $System_Drawing_Point.Y = 30 
    $btnQuit.Location = $System_Drawing_Point 
    $btnQuit.add_Click($Quit) 
 
    $Main1.Controls.Add($btnQuit) 
    ### End Button Quit

    ### Button Save
    $btnSave.UseVisualStyleBackColor = $True 
    $btnSave.Text = 'Save' 
 
    $btnSave.DataBindings.DefaultDataSourceUpdateMode = 0 
    $btnSave.TabIndex = 2 
    $btnSave.Name = 'btnSave' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 75 
    $System_Drawing_Size.Height = 23 
    $btnSave.Size = $System_Drawing_Size 
    #$btnSave.Anchor = 9 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 450
    $System_Drawing_Point.Y = 30 
    $btnSave.Location = $System_Drawing_Point 
    $btnSave.add_Click($Save) 

 
    $Main1.Controls.Add($btnSave) 
    ### End Button Save

    #$ServerName.ValueMember = "VMName"

    $ServerName.DataSource = $VMs.VMName | Sort-Object
    $ServerName.DisplayMember = 'VMName'
    $ServerName.Name = 'txtComputerList' 
    $ServerName.TabIndex = 0 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 198 
    $System_Drawing_Size.Height = 20 
    $ServerName.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 13 
    $System_Drawing_Point.Y = 33 
    $ServerName.Location = $System_Drawing_Point 
    $ServerName.DataBindings.DefaultDataSourceUpdateMode = 0 
    $ServerName.add_SelectedIndexChanged($GetServerData)
    $Main1.Controls.Add($ServerName) 

    ### Datagridview definitions

    $dataGridView.RowTemplate.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(255,0,128,0) 
    $dataGridView.Name = 'dataGridView' 
    $dataGridView.DataBindings.DefaultDataSourceUpdateMode = 0 
    #$dataGridView.ReadOnly = $True 
    $dataGridView.AllowUserToDeleteRows = $False 
    $dataGridView.RowHeadersVisible = $False 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 870 
    $System_Drawing_Size.Height = 260 
    $dataGridView.Size = $System_Drawing_Size 
    $dataGridView.TabIndex = 8 
    $dataGridView.Anchor = 15 
    $dataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::AllCells

 
 
    $dataGridView.AllowUserToAddRows = $False 
    $dataGridView.ColumnHeadersHeightSizeMode = 2 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 13 
    $System_Drawing_Point.Y = 70 
    $dataGridView.Location = $System_Drawing_Point 
    $dataGridView.AllowUserToOrderColumns = $True 
    $dataGridView.add_CellContentDoubleClick($LaunchCompMgmt) 
    $dataGridView.AutoGenerateColumns = $False
    #$dataGridView.AutoResizeColumns([System.Windows.Forms.DataGridViewAutoSizeColumnsMode.AllCells]::AllCells) 
    #$DataGridViewAutoSizeColumnsMode.AllCells 
 
    $Main1.Controls.Add($dataGridView) 

    ### Datagridview definitions
    ### Datagridview columns
    $CLM_VMName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $CLM_VMName.Name = "VMName"
    $CLM_VMName.HeaderText = "VMName"
    $CLM_VMName.DataPropertyName = "VMName"
    $CLM_VMName.AutoSizeMode = "AllCells"

    $CLM_Type = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $CLM_Type.Name = "Type"
    $CLM_Type.HeaderText = "Type"
    $CLM_Type.DataPropertyName = "Type"
    $CLM_Type.AutoSizeMode = "AllCells"

    $CLM_DriveParams = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $CLM_DriveParams.Name = "DriveParams"
    $CLM_DriveParams.HeaderText = "DriveParams"
    $CLM_DriveParams.DataPropertyName = "DriveParams"
    $CLM_DriveParams.AutoSizeMode = "AllCells"

    $CLM_Path = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $CLM_Path.Name = "Path"
    $CLM_Path.HeaderText = "Path"
    $CLM_Path.DataPropertyName = "Path"
    $CLM_Path.AutoSizeMode = "AllCells"


    $CLM_NXSCSINo = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $CLM_NXSCSINo.Name = "NXSCSINo"
    $CLM_NXSCSINo.HeaderText = "NXSCSINo"
    $CLM_NXSCSINo.DataSource = $NXSCSINos
    $CLM_NXSCSINo.ValueMember = "NXSCSINo"
    $CLM_NXSCSINo.DisplayMember = "NXSCSINo"
    $CLM_NXSCSINo.DataPropertyName = "NXSCSINo"
    $CLM_NXSCSINo.AutoSizeMode = "AllCells"

    $CLM_NXContainer = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $CLM_NXContainer.Name = "NXContainer"
    $CLM_NXContainer.HeaderText = "NXContainer"
    $CLM_NXContainer.DataSource = $ADSF_selection
    $CLM_NXContainer.ValueMember = "NXContainer"
    $CLM_NXContainer.DisplayMember = "NXContainer"
    $CLM_NXContainer.DataPropertyName = "NXContainer"
    $CLM_NXContainer.AutoSizeMode = "AllCells"

    $dataGridView.Columns.AddRange($CLM_VMName,$CLM_Type,$CLM_DriveParams,$CLM_Path,$CLM_NXSCSINo,$CLM_NXContainer)


    ### End of Datagridview columns
    ### Batch name text box
    $BatchName.Text = '' 
    $BatchName.Name = 'BatchName' 
    $BatchName.TabIndex = 0 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 70
    $System_Drawing_Size.Height = 20 
    $BatchName.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 680
    $System_Drawing_Point.Y = 33 
    $BatchName.Location = $System_Drawing_Point 
    $BatchName.DataBindings.DefaultDataSourceUpdateMode = 0 
 
    $Main1.Controls.Add($BatchName) 
    ### End Batch name text box


    ### Batch name label
    $BatchLabel.Text = 'BatchName' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 70
    $System_Drawing_Size.Height = 20 
    $BatchLabel.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 680
    $System_Drawing_Point.Y = 20 
    $BatchLabel.Location = $System_Drawing_Point 

 
    $Main1.Controls.Add($BatchLabel) 
    ### End Batch name label

  ### MAC checkbox
    $MACCheck.Text = '' 
    $MACCheck.Name = 'CloneMAC' 
    $MACCheck.TabIndex = 0 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 25
    $System_Drawing_Size.Height = 25
    $MACCheck.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 540
    $System_Drawing_Point.Y = 33 
    $MACCheck.Location = $System_Drawing_Point 
    $MACCheck.DataBindings.DefaultDataSourceUpdateMode = 0 
 
    $Main1.Controls.Add($MACCheck) 
    ### End MAC checkbox
    
    ### MAC name label
    $MACLabel.Text = 'Clone MAC' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 70
    $System_Drawing_Size.Height = 20 
    $MACLabel.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 540
    $System_Drawing_Point.Y = 20 
    $MACLabel.Location = $System_Drawing_Point 

 
    $Main1.Controls.Add($MACLabel) 
    ### End MAC name label

     ### MAC checkbox
    $hwTimeZoneCheck.Text = '' 
    $hwTimeZoneCheck.Name = 'hwTimeZone' 
    $hwTimeZoneCheck.TabIndex = 0 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 25
    $System_Drawing_Size.Height = 25
    $hwTimeZoneCheck.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 620
    $System_Drawing_Point.Y = 33 
    $hwTimeZoneCheck.Location = $System_Drawing_Point 
    $hwTimeZoneCheck.DataBindings.DefaultDataSourceUpdateMode = 0 
 
    $Main1.Controls.Add($hwTimeZoneCheck) 
    ### End MAC checkbox
    
    ### MAC name label
    $hwTimezoneLabel.Text = 'Use local timezone' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 70
    $System_Drawing_Size.Height = 40 
    $hwTimezoneLabel.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 620
    $System_Drawing_Point.Y = 5 
    $hwTimezoneLabel.Location = $System_Drawing_Point 

 
    $Main1.Controls.Add($hwTimezoneLabel) 
    ### End MAC name label




    ### Server name label
    $ServerLabel.Text = 'Servername' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 70
    $System_Drawing_Size.Height = 20 
    $ServerLabel.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 13
    $System_Drawing_Point.Y = 20 
    $ServerLabel.Location = $System_Drawing_Point 

 
    $Main1.Controls.Add($ServerLabel) 
    ### End Server name label


    ### Checkpoint notification label
    $labelCheckp.Text = 'THIS VM HAS A CHECKPOINT`nPlease remove it and click LoadVMdisk button' 
    $System_Drawing_Size = New-Object System.Drawing.Size 
    $System_Drawing_Size.Width = 300
    $System_Drawing_Size.Height = 35 
    $labelCheckp.Size = $System_Drawing_Size 
    $System_Drawing_Point = New-Object System.Drawing.Point 
    $System_Drawing_Point.X = 500
    $System_Drawing_Point.Y = 27 
    $labelCheckp.Location = $System_Drawing_Point 
    $labelCheckp.BackColor = "Red"
    $labelCheckp.Visible = $False
 
    $Main1.Controls.Add($labelCheckp) 
    ### End Checkpoint notification label

    #Show the Form 
    Write-Debug "ShowDialog()" 
    $Main1.ShowDialog()| Out-Null 



}





# You can modify this function for your needs.
# Save all parameters which are satic to here 

 Function global:Move-NTtNXLazyMove{
 Param(

 [Parameter(Mandatory=$True,Position=1)] [string]$Batch,
 [Parameter(Mandatory=$True,Position=2)] [securestring]$NXPassword,
 [Parameter(Mandatory=$True,Position=3)] [DateTime]$StartTime,
 [Parameter(Mandatory=$True,Position=4)] [int]$SimultaneusCount,
 [Parameter(Mandatory=$True,Position=5)] [int]$Streams
 [Parameter(Mandatory=$True,Position=6)] [string]$LogPath
 

 )
   $Cluster = "HyperV Cluster ip or name"
   $Server = "Nutanixcluster ip or name"
   $User = "username"
   $Unc = "\\unc_path_to_qemu-img\folder"     # Last part is case sensitive, don't ask me why....
   $drive = "z:"
   $LogPath = "c:\log"
  
   # SimultaneusCount, How many concurrent vhd(x) moves
   # Streams, check qemu-img parameter "-m" min 1, max 16


    
   Move-HVtNX -HyperVCluster $Cluster -BatchName $Batch -StartTime $StartTime -NXServer $Server -NXUser $User -NXPassword $NXPassword -UncPathToQemuShare $Unc -QemuDrive $drive -SimultaneusCount $SimultaneusCount -Streams $Streams -LogFolder $LogPath

 }

 

export-modulemember -function Move-HVtNX, Open-HVtNXConfigForm, Move-NTtNXLazyMove