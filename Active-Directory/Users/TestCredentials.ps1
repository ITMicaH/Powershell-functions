#Test if AD credentials are valid
function Test-ADCredentials
{
    param(
        [Paramater(mandatory)]
        [string]
        $UserName, 

        [Paramater(mandatory)]
        [string]
        $Password,

        [string]
        $Domain
    )
    switch -Regex ($UserName)
    {
        '\\' {
            $Domain = Split-Path $UserName
            $UserName = Split-Path $UserName -Leaf
        }
        '@'  {
            throw "UPN is not a supported username format"
        }
    }
    If ($Domain)
    {
        if ($Domain -match '\.')
        {
            $Domain = "WinNT://$Domain"
        }
        else
        {
            If ($ADObject = ([adsisearcher]"(&(objectClass=trustedDomain)(flatname=$Domain))").FindOne())
            {
                $Domain = "WinNT://$($ADObject.Properties.cn)"
            }
            else
            {
                throw "Unable to resolve domain $Domain"
            }
        }
    }
    [DirectoryServices.DirectoryEntry]::new($Domain,$UserName,$Password).psbase.name -ne $null
}
