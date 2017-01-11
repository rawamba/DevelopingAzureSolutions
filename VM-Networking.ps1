# Author: Roger Wamba, Ottawa - ON Canada
# Last Update: January 1st, 2017
# Create a virtual network with two subnets with Security groups and on VM in each VM


$ErrorActionPreference = "Stop" # Stop at the first error

#Login and set subscrition context
#Login-AzureRmAccount
Set-AzureRmContext -SubscriptionName "MSDN Offer Virtual Machines"

#Create a resource group
$location = "East US"
$myResourceGroupName = "Exam70532-Networking-rg"

#For practice purposes, we always remove this resourceGroup
#Remove-AzureRmResourceGroup -Name $myResourceGroupName

#Recreate resource group
$myResourceGroup = New-AzureRmResourceGroup -Name $myResourceGroupName -Location $location -Tag @{ environment = "dev" }
write-host -ForegroundColor Green "Successfully created resource group " $myResourceGroupName

#Create storage accounts for Front End (Web) and back end (DBs) network areas
$myStorageAccountNameFE = "exam70532frontend" 
$myStorageAccountFE = New-AzureRmStorageAccount -ResourceGroupName $myResourceGroup.ResourceGroupName -Name $myStorageAccountNameFE -SkuName "Standard_LRS" -Kind "Storage" -Location $location

$myStorageAccountNameBE = "exam70532backend" 
$myStorageAccountBE = New-AzureRmStorageAccount -ResourceGroupName $myResourceGroup.ResourceGroupName -Name $myStorageAccountNameBE -SkuName "Standard_LRS" -Kind "Storage" -Location $location
write-host -ForegroundColor Green "Successfully created storage accounts: " $myStorageAccountBE.StorageAccountName $myStorageAccountFE.StorageAccountName

#Create a virtual network

#1. Create Network Security Groups

#1.a. Create a new rule to allow traffic from the Internet to port 443 and 3389
$NSGRule443 = New-AzureRmNetworkSecurityRuleConfig -Name 'WEB' -Direction Inbound -Priority 100 -Access Allow -SourceAddressPrefix 'INTERNET' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange '443' -Protocol TCP
$NSGRule3389 = New-AzureRmNetworkSecurityRuleConfig -Name 'RDP' -Direction Inbound -Priority 101 -Access Allow -SourceAddressPrefix 'INTERNET' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange '3389' -Protocol TCP
write-host -ForegroundColor Green "Successfully created Rules" $NSGRule443.Name $NSGRule3389.Name

#1.b Create two security groups with above rules
$NSGFrontEnd = New-AzureRmNetworkSecurityGroup -Name "FrontEnd-nsg" -Location $Location -ResourceGroupName $myResourceGroupName -SecurityRules $NSGRule443, $NSGRule3389
$NSGBackEnd = New-AzureRmNetworkSecurityGroup -Name "BackEnd-nsg" -Location $Location -ResourceGroupName $myResourceGroupName -SecurityRules $NSGRule3389, $NSGRule443
write-host -ForegroundColor Green "Successfully created 2 network security groups: " $NSGFrontEnd.Name $NSGBackEnd.Name


#2. Create FrontEnd and BackEnd subnets
$myFrontEndSubnetName = "Exam70532-FrontEnd-Subnet"
$myBackEndSubnetName = "Exam70532-BackEnd-Subnet"
$myFrontEndSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $myFrontEndSubnetName -AddressPrefix 10.0.1.0/24 -NetworkSecurityGroup $NSGFrontEnd
$myBackEndSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $myBackEndSubnetName -AddressPrefix 10.0.2.0/24 -NetworkSecurityGroup $NSGBackEnd
write-host -ForegroundColor Green "Successfully created subnets: " $myFrontEndSubnet.Name $myBackEndSubnet.Name


#3. Create the Virtual Network with two subnets
$myVnet = New-AzureRmVirtualNetwork -Location $location -Name "Exam70532-Networking-Vnet" -ResourceGroupName $myResourceGroupName -AddressPrefix 10.0.0.0/16 -Subnet $myFrontEndSubnet, $myBackEndSubnet
write-host -ForegroundColor Green "Successfully created Virtual network: " $myVnet.Name

$y=$myVnet.Subnets.Count

for ($i=0; $i -lt $y; $i++)
{
# Create a VM per subnet

$pipName = $myVnet.Subnets[$i].Name + "-pip"
$nicName = $myVnet.Subnets[$i].Name + "-nic"
$subNetTier = $myVnet.Subnets[$i].Name.split("-"" ")[1]
$vmName =  $subNetTier + "-vm"



#Create a public IP address and network interface
#4.1 Create public IP
$myPublicIp = New-AzureRmPublicIpAddress -AllocationMethod Dynamic -ResourceGroupName $myResourceGroupName -Name $pipName  -Location $location  -IpAddressVersion IPv4
write-host -ForegroundColor Green "Successfully created public Ip: " $myPublicIp.Name

#4.2 Create NIC

$myNIC = New-AzureRmNetworkInterface -Location $location -Name $nicName -ResourceGroupName $myResourceGroupName -SubnetId $myVnet.Subnets[$i].Id -PublicIpAddressId $myPublicIp.Id -NetworkSecurityGroupId $NSGFrontEnd.Id
write-host -ForegroundColor Green "Successfully created Network Interface card: " $nicName

# Create the virtual machine
#1. Set admin login credentials
$cred = Get-Credential -Message "Type the name and password of the local administrator account."
write-host -ForegroundColor Green "Successfully captured admin login"

#2. Create the configuration object for the virtual machine
$myVM = New-AzureRmVMConfig -VMName $vmName -VMSize "Standard_A0"
write-host -ForegroundColor Green "Successfully created Vm Configuration object for: " $myVM.Name

#3. Configure operating system settings for the VM.
$myVM = Set-AzureRmVMOperatingSystem -VM $myVM -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
write-host -ForegroundColor Green "Successfully Configured operating system"
 
#4. Define the image to use to provision the VM. 
#$myVM = Set-AzureRmVMSourceImage -VM $myVM -PublisherName "MicrosoftVisualStudio" -Offer "VisualStudio" -Skus "VS-2015-Ent-VSU3-AzureSDK-291-WS2012R2" -Version "latest"
$myVM = Set-AzureRmVMSourceImage -VM $myVM -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2012-R2-Datacenter" -Version "latest"
write-host -ForegroundColor Green "Successfully Defined image"

#5. Add the Network interface card
$myVM = Add-AzureRmVMNetworkInterface -VM $myVM -Id $myNIC.Id
write-host -ForegroundColor Green "Successfully Added NIC to VM: " $myVM.Name

#6. Define the name and location of the VM hard disk
 $blobPath = "vhds/" + $subNetTier + "OsDisk.vhd"
 $osDiskUri = $myStorageAccountFE.PrimaryEndpoints.Blob.ToString() + $blobPath
 write-host -ForegroundColor Green "Successfully defined name and location of disk blob: " $osDiskUri

#7. Add the operating system disk information to the VM configuration.
$osDiskName = $subNetTier + "OsDisk";
$myVM = Set-AzureRmVMOSDisk -VM $myVM -Name $osDiskName -VhdUri $osDiskUri -CreateOption fromImage
write-host -ForegroundColor Green "Successfully added OS disk to VM config: " $osDiskName

#8. Finally, create the virtual machine
New-AzureRmVM -ResourceGroupName $myResourceGroupName -Location $location -VM $myVM
write-host -ForegroundColor Green "Successfully created the VM: " $myVM.Name

#9 Set DNS label
$dnsLabel = "rogerexam" + $subNetTier.ToLower()
$ip =get-AzureRmPublicIpAddress -Name $myPublicIp.Name -ResourceGroupName $myResourceGroupName
$ip.DnsSettings += @{DomainNameLabel = $dnsLabel}  
write-host -ForegroundColor Green "Successfully set dns label of VM:" $i "to" $dnsLabel                 
Set-AzureRmPublicIpAddress -PublicIpAddress $ip  

    
}


# 6.10 Finally export template
Export-AzureRmResourceGroup -ResourceGroupName $myResourceGroupName -Path C:\Users\Roger\OneDrive\Certifications\070-532\Exam70532RGConfigNetworking.json -IncludeParameterDefaultValue -IncludeComments
