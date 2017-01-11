#Author: Roger Wamba - MCP - rawamba@pacosoft.com
#Last Modified: Ottawa, 1-11-2017
#Create a Developer Virtual Machine (VS 2015 enterprise + Windows Server 2012 R2)
$ErrorActionPreference = "Stop" # Stop at the first error

# Login
Login-AzureRmAccount

#set subscrition context if more than one subscription in account
Set-AzureRmContext -SubscriptionName "<subscription here>"

#Set Location
$location = "East US"

# Create a resource group (For practice purposes, we always remove this resourceGroup and attempt to re-create)
$myResourceGroupName = "DevMachine-rg"
$myResourceGroup = $null;
try
{
Remove-AzureRmResourceGroup -Name $myResourceGroupName
}
catch
{
 #Ignore and continue
}
finally 
{
    # ResourceGroup doesn't exist, or has been remove above, so create it
    $myResourceGroup = New-AzureRmResourceGroup -Name $myResourceGroupName -Location $location
    write-host -ForegroundColor Green "Successfully created resource group: " $myResourceGroupName
}


# Create a storage account if none existant
$myStorageAccountName = "devmachinesa" 
$acountNameStatus = Get-AzureRmStorageAccountNameAvailability -Name $myStorageAccountName

If ($acountNameStatus.NameAvailable -eq $true) {
write-host -ForegroundColor Green "Storage account name Available. Now creating account .... "
$myStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $myResourceGroupName -Name $myStorageAccountName -SkuName "Standard_LRS" -Kind "Storage" -Location $location
write-host -ForegroundColor Green "Successfully created Storage account: " $myStorageAccountName
}
else
{
write-host -BackgroundColor white -ForegroundColor Red -Object "Account name already taken"
}

try
{
# Set storage context for your current session to the above storage
Set-AzureRmCurrentStorageAccount -ResourceGroupName $myResourceGroupName -StorageAccountName $myStorageAccountName
}
catch
{
# account already exist 
write-host -BackgroundColor white -ForegroundColor Red -Object "Exception ignored while seting default storage context"
}

# Create virtual network where the VM will reside

#Create NSG rule
$NSGRule3389 = New-AzureRmNetworkSecurityRuleConfig -Name 'RDP' -Direction Inbound -Priority 101 -Access Allow -SourceAddressPrefix 'INTERNET' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange '3389' -Protocol TCP
write-host -ForegroundColor Green "Successfully created security Rule:" $NSGRule3389.Name

#Create NSG
$NSGDevMachine = New-AzureRmNetworkSecurityGroup -Name "DevMachineSubnet-nsg" -Location $Location -ResourceGroupName $myResourceGroupName -SecurityRules $NSGRule3389
write-host -ForegroundColor Green "Successfully created 1 network security group: " $NSGDevMachine.Name

#Create Subnet 
$devMachineSubnetName = "devMachine-Subnet"
$devMachineSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $devMachineSubnetName -AddressPrefix "10.0.0.0/24" -NetworkSecurityGroup $NSGDevMachine
write-host -ForegroundColor Green "Successfully created subnet: " $devMachineSubnet.Name

#Create Vnet
$devMachineVnet = "devMachine-Vnet"
$myVnet = New-AzureRmVirtualNetwork -Name $devMachineVnet -ResourceGroupName $myResourceGroupName -Location $location -AddressPrefix "10.0.0.0/16" -Subnet $devMachineSubnet
write-host -ForegroundColor Green "Successfully created Virtual network: " $myVnet.Name


# Create the VM in the subnet - you can use any name for the below variables - I just like to link them together so I can easily remember
$devName = "roger"
$vmName =  $devName + $devMachineSubnet.Name.split("-"" ")[0].ToLower()
$pipName = $vmName + "-pip"
$nicName = $vmName + "-nic"

# Create public IP
$myPublicIp = New-AzureRmPublicIpAddress -AllocationMethod Dynamic -ResourceGroupName $myResourceGroupName -Name $pipName  -Location $location  -IpAddressVersion IPv4
write-host -ForegroundColor Green "Successfully created public Ip: " $myPublicIp.Name

# Create NIC
$myNIC = New-AzureRmNetworkInterface -Location $location -Name $nicName -ResourceGroupName $myResourceGroupName -SubnetId $myVnet.Subnets[0].Id -PublicIpAddressId $myPublicIp.Id -NetworkSecurityGroupId $NSGDevMachine.Id
write-host -ForegroundColor Green "Successfully created Network Interface card: " $myNIC.Name

# Create the virtual machine
#1. Set admin login credentials
$cred = Get-Credential -Message "Type the name and password of the local administrator account."
write-host -ForegroundColor Green "Successfully captured admin login"

#2. Create the configuration object for the virtual machine
$myVM = New-AzureRmVMConfig -VMName $vmName -VMSize "Standard_A1"
write-host -ForegroundColor Green "Successfully created Vm Configuration object for: " $myVM.Name

#3. Configure operating system settings for the VM.
$myVM = Set-AzureRmVMOperatingSystem -VM $myVM -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
write-host -ForegroundColor Green "Successfully Configured operating system"
 
#4. Define the image to use to provision the VM. 
$myVM = Set-AzureRmVMSourceImage -VM $myVM -PublisherName "MicrosoftVisualStudio" -Offer "VisualStudio" -Skus "VS-2015-Ent-VSU3-AzureSDK-291-WS2012R2" -Version "latest"
write-host -ForegroundColor Green "Successfully Defined image for: " $myVM.Name

#5. Add the Network interface card
$myVM = Add-AzureRmVMNetworkInterface -VM $myVM -Id $myNIC.Id
write-host -ForegroundColor Green "Successfully Added NIC to VM: " $myNIC.Name

#6. Define the name and location of the VM hard disk
 $blobPath = "vhds/" + $myVM.Name + "OsDisk.vhd"
 $osDiskUri = $myStorageAccount.PrimaryEndpoints.Blob.ToString() + $blobPath
 write-host -ForegroundColor Green "Successfully defined name and location of disk blob: " $osDiskUri

#7. Add the operating system disk information to the VM configuration.
$osDiskName = $myVM.Name + "OsDisk";
$myVM = Set-AzureRmVMOSDisk -VM $myVM -Name $osDiskName -VhdUri $osDiskUri -CreateOption fromImage
write-host -ForegroundColor Green "Successfully added OS disk to VM config: " $osDiskName

#8. Finally, create the virtual machine
New-AzureRmVM -ResourceGroupName $myResourceGroupName -Location $location -VM $myVM
write-host -ForegroundColor Green "Successfully created the VM: " $myVM.Name "in" $location

#9 Set DNS label
$dnsLabel =$myVM.Name.ToLower()
$ip =get-AzureRmPublicIpAddress -Name $myPublicIp.Name -ResourceGroupName $myResourceGroupName
$ip.DnsSettings += @{DomainNameLabel = $dnsLabel}  
write-host -ForegroundColor Green "Successfully set dns label of VM:" $myVM.Name "to" $dnsLabel                 
Set-AzureRmPublicIpAddress -PublicIpAddress $ip  
