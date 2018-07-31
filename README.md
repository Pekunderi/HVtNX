# HVtNX
Hyper-V Cluster to Nutanix AHV migration tool is a single file powershell script, which hopefully will help some people to migrate VMs from Hyper-V cluster to the Nutanix AHV cluster. This script should be able to work with Windows Server 2012 and 2012R2 clusters.

You are using this script at your own risk. There are absolutelu no warranty or wathsoever. 

# Why
This tool was made because I need to migrate bunch of VMs form Hyper-V cluster to Nutanix AHV and I could't find any suitable tool for this purpose which could automate whole process. I know there is lot of things what sould be done differently, but it was made in hurry, and it was good enough to do it's job.

# Pros
- Source VM will be intact
- Settings, like CPU's, Memory, NIC's, MAC's (optional), VLAN's will be migrated
- No hassle with disk paths, settings, MAC's, VLAN's
- Multiple VMs and multiple disks could be migrated at same time
- Migration settings, and VM's to migrated can be planned in advance
- Migration can be scheduled
- Migration could be done same time from multiple hyper-v clusters
- Source VM will be shutdown automatically, at the time when VM migration begins
- 

# Cons
- VirtIO drivers need to be installed before migration
- IP address(es) must be configured in Windows machines, and sometimes in Linux VM's as well
- Not suitable for VM's which have huge virtual disk(s), like over 500GB, it would take long time to migrate
- There is bugs in the code. This script was done because I just need a tool, not a bug free program which will do everything
- Gen2 VM's, might be using UEFI boot
 - Windows machines might work, but UEFI boot mode must be set using acli
 - Linux machines are difficult to get working
- GUI for make necessary configurations
- Human readable settings in the Hyper-V VM:s Notes field

# Requirements
- Hyper-V clusters: Windows Server 2012 and Windows Server 2012 R2
- VLAN is configured in virtual nics VLAN ID field
- Checkpoints are removed, if there are any
- Nutanix CMDLets are installed, activated and it's correct version
- Machine which is used to run this script has full access to Nutanix cluster and to the Hyper-V cluster (psremote, WMI, etc)
- Hyper-V Cluster host has access to AFSF share
- qemu-img executable and libraries are copied to ADSF share 
- Hyper-V hosts has psremoting enabled, and depens on your settings, but Powershell Executionpolicy might need to be set to quite permissive mode.
- You have more than 40 VM's which need to migrated. I could not see that it's worth to use this script if there is only few VM's
- Plenty of knowledge of powershell, eager to find all problems and lot of time..... :)


# Howto
- Check requirements!!!
- Read whole script.
- You know what you are doing, do you?
- Are you absolutely sure did you fully understand previous line? ;)

1. Copy the qemu-img executable to ADSF share to saome folder. It will be needed later. 
2. Download, install Nutanix CMDLets in the server where script will be running
3. Click the Nutanix CMDLet icon in start menu and follow the instructions
4. Edit last function on the script named as Move-NTtNXLazyMove
5. Import the module using command

	`Import-Module .\HVtNX.psm1`
6. Run configuration tool 

	`Open-HVtNXConfigForm -ClusterName "YOURHYPERVCLUSTERNAME" -ADSFContainers "FirstContaine","SecondContainer"`
7. Migrate VM's using 

  `Move-NTNXLazyMove -Batch batchname -StartTime (get-date) -SimultaneusCount 4 -Streams 16 -LogPath LogPath`

## Open-HVtNXConfigForm
- Synopsis: 
  Graphical UI to prepare Hyper-V Cluster VMs to convert and import them to Nutanix AHV
- Description: 
  Graphical UI will help to prepare disk configuration before migrating them to Nutanix AHV. 
- Settings
	- Clone MAC: This setting will copy MAC address(es) from hyper-v virtual machine to Nutanix VM
	- Local timezone: This setting will use Nutanix timezone on nutanix VM rather than UTC
	- BatchName: 	User selectable job name. 
	- SCSI id: 	Nutanix VM scsi id
- Parameters
	- ClusterName:  Name of the Hyper-V Cluster.
	- ADSFContainers: Array of the Nutanix Storage Containers.
- Example: 
`Open-HVtNXConfigForm -$ClusterName HYPERVCLUSTERNAME -$ADSFContainers "Cont1","Cont2","Cont3","Cont4"`


## Move-NTtNXLazyMove
- Synopsis: 
  Migration function, with predefined variables
- Description: 
 Function which is used to migrate VM's from Hyper-V Cluster to Nutanix AHV. It hs variables, which must be definet by user, but it has to be only one time. 
- Parameters
	- "Batch": 		Name of the batch job
	- "StartTime":		DateTime field, like ((Get-Date).AddHours(1)), it will start after an hour
	- "SimultaneusCount":	Concurrent virtual disk moves
	- "Streams":		Check qemu-img parameter -m
	- "LogPath": 		Path where log files are stored, do not use trailing backslash
	- "NXPassword"		Nutanix password in securestring. Just leave command without this parameter, and it will ask it 
- Example: 
`Move-NTtNXLazyMove -Batch batchname -StartTime (get-date) -SimultaneusCount 4 -Streams 16 -LogPath LogPath`
