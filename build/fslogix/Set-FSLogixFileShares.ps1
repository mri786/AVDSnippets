
# Set Required Params
$userPermissionGroup = '#{variables.userPermissionGroup}#'
$storageAccountName = '#{variables.storageAccountName}#'
$storageAccountRG = '#{variables.storageAccountRG}#'
$shareName = '#{variables.profileShareName}#'
$creatorId = 'CREATOR OWNER'
$authUsersId = 'Authenticated Users'
$builtinUsers = 'Users'
$mappedDrive = 'P'
$clientid = '#{variables.azAccountClientid}#'

# Install and Connect Required Modules
try {
    Install-PackageProvider -Name NuGet -Confirm:$False -MinimumVersion 2.8.5.201 -force
    Install-Module -Name Az.Storage -Confirm:$False -Scope AllUsers -Repository PSGallery -Force
    Install-Module -Name Az.ManagedServiceIdentity -Confirm:$False -Scope AllUsers -Repository PSGallery -Force
    Connect-AzAccount -Identity -AccountId $ClientId
    $ctx = Get-AzContext
} catch {
    throw 'ERROR - Prereqs failed'
}

Set-SmbClientConfiguration -EncryptionCiphers 'AES_256_GCM, AES_128_GCM, AES_128_CCM, AES_256_CCM' -Confirm:$False -Force

$AccountKey = (Get-AzStorageAccountKey -Name $storageAccountName -ResourceGroupName $storageAccountRG).where({
        $PSItem.KeyName -eq 'key1'
    }).value | ConvertTo-SecureString -AsPlainText -Force

$profilePath = Join-Path -Path "\\$storageAccountName.file.$($ctx.Environment.StorageEndpointSuffix)" -ChildPath $shareName
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ("localhost\$storageAccountName", $AccountKey)
try {
    New-PSDrive -Name $mappedDrive -PSProvider FileSystem -Root $profilePath -Credential $credObject | Out-Null
} catch {
    throw "ERROR - Failed to map drive"
}

# Check mapped drive
$mappedDrivePath = '{0}:\' -f $mappedDrive
$testPath = Test-Path -Path $mappedDrivePath
if (!($testPath)) {
    throw "ERROR - Mapped drive not found"
}

# Define properties for new ACL rules
$ruleProperties = @(
    (
        $userPermissionGroup,
        "Modify",
        "NoPropagateInherit",
        "Allow"
    ),
    (
        $creatorId,
        "Modify",
        "ContainerInherit, ObjectInherit",
        "InheritOnly",
        "Allow"
    )
)

# Create new ACL rule objects
$newRules = $ruleProperties.ForEach({ New-Object System.Security.AccessControl.FileSystemAccessRule($PSItem) })

# Get existing ACL
$acl = Get-Acl -Path $mappedDrivePath
Write-Host "Existing ACL:"
Write-Host "====================="
($acl.Access).ForEach({
        $rule = $PSItem
        $properties = ($rule | Get-Member -MemberType Property).Name
        $properties.ForEach({
                Write-Host "$PSItem : $($rule.$PSItem)"
            })
        Write-Host "---------------------"
    })

# Removing default authenticated users permission
$existingAuthUsersRule = ($acl.Access).Where({ $PSItem.IdentityReference -imatch $authUsersId })
$existingAuthUsersRule.ForEach({ $acl.RemoveAccessRule($PSItem) })

# Removing default built in users permission
$existingAuthUsersRule = ($acl.Access).Where({ $PSItem.IdentityReference -imatch $builtinUsers })
$existingAuthUsersRule.ForEach({ $acl.RemoveAccessRule($PSItem) })

# Removing default Creator Owner permission
$existingCreatorRule = ($acl.Access).Where({ $PSItem.IdentityReference -imatch $creatorId })
$existingCreatorRule.ForEach({ $acl.RemoveAccessRule($PSItem) })

# Add new rules
$newRules.ForEach({ $acl.addAccessRule($PSItem) })

# Set new ACL on SMB share
Write-Host "New ACL:"
Write-Host "====================="
($acl.Access).ForEach({
        $rule = $PSItem
        $properties = ($rule | Get-Member -MemberType Property).Name
        $properties.ForEach({
                Write-Host "$PSItem : $($rule.$PSItem)"
            })
        Write-Host "---------------------"
    })
try {
    Set-Acl -Path $mappedDrivePath -AclObject $acl
} catch {
    throw "ERROR - Failed to set new ACL"
}

Remove-PSDrive -Name $mappedDrive -Force

#############################################################################################################
# Set NTFS Permissions on the Redirection File Share
#############################################################################################################

$shareName = '#{variables.redirectionShareName}#'
$mappedDrive = 'R'
$sourceFilePath = "#{variables.redirectionSourceFilePath}#" # Must be double quotes to accept $env:temp in path!!

$profilePath = Join-Path -Path "\\$storageAccountName.file.$($ctx.Environment.StorageEndpointSuffix)" -ChildPath $shareName
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ("localhost\$storageAccountName", $AccountKey)
try {
    New-PSDrive -Name $mappedDrive -PSProvider FileSystem -Root $profilePath -Credential $credObject
} catch {
    throw "ERROR - Failed to map drive"
}

# Check mapped drive
$mappedDrivePath = '{0}:\' -f $mappedDrive
$testPath = Test-Path -Path $mappedDrivePath
if (!($testPath)) {
    throw "ERROR - Mapped drive not found"
}$sour

# Copy redirections file to redirection share
Write-Host "Copying $sourceFilePath to $mappedDrivePath"
Copy-Item -Path $sourceFilePath -Destination $mappedDrivePath -Force -Confirm:$false -Verbose
$testFile = Join-Path -Path $mappedDrivePath -ChildPath $(Split-Path -leaf $sourceFilePath)
if (!(Test-Path -Path $testFile)) {
    Write-Host 'Error, cannot find redirections file on redirection share!'
} else {
    Write-Host 'redirections file found on share, copy successful'
}

# Define properties for new ACL rules
$ruleProperties = @(
    (
        $userPermissionGroup,
        "ReadData, ReadPermissions, ReadAttributes, ReadExtendedAttributes",
        "ContainerInherit,ObjectInherit",
        "NoPropagateInherit",
        "Allow"
    )
)

# Create new ACL rule objects
$newRules = New-Object System.Security.AccessControl.FileSystemAccessRule($ruleProperties)

# Get existing ACL
$acl = Get-Acl -Path $mappedDrivePath
Write-Host "Existing ACL:"
Write-Host "====================="
($acl.Access).ForEach({
        $rule = $PSItem
        $properties = ($rule | Get-Member -MemberType Property).Name
        $properties.ForEach({
                Write-Host "$PSItem : $($rule.$PSItem)"
            })
        Write-Host "---------------------"
    })

# Removing default authenticated users permission
$existingAuthUsersRule = ($acl.Access).Where({ $PSItem.IdentityReference -imatch $authUsersId })
$existingAuthUsersRule.ForEach({ $acl.RemoveAccessRule($PSItem) })

# Removing default Creator Owner permission
$existingCreatorRule = ($acl.Access).Where({ $PSItem.IdentityReference -imatch $creatorId })
$existingCreatorRule.ForEach({ $acl.RemoveAccessRule($PSItem) })

# Add new rules
$newRules.ForEach({ $acl.addAccessRule($PSItem) })

# Set new ACL on SMB share
Write-Host "New ACL:"
Write-Host "====================="
($acl.Access).ForEach({
        $rule = $PSItem
        $properties = ($rule | Get-Member -MemberType Property).Name
        $properties.ForEach({
                Write-Host "$PSItem : $($rule.$PSItem)"
            })
        Write-Host "---------------------"
    })
try {
    Set-Acl -Path $mappedDrivePath -AclObject $acl
} catch {
    throw "ERROR - Failed to set new ACL"
}

Remove-PSDrive -Name $mappedDrive -Force