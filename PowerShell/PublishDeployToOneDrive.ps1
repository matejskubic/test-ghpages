#$VerbosePreference=[System.Management.Automation.ActionPreference]::Continue

<#
.SYNOPSIS
TFS CheckIn of latest successfull *AdactaLoc* AX model

.PARAMETER Force

#get token from http://go.microsoft.com/fwlink/p/?LinkId=193157
# http://dev.onedrive.com/
# http://msdn.microsoft.com/en-us/library/dn631844.aspx

# LiveApi - url starting with      https://login.live.com
# Server Side: http://msdn.microsoft.com/en-us/library/hh243649.aspx
#   - Auth Code: https://login.live.com/oauth20_authorize.srf?client_id=CLIENT_ID&scope=SCOPES&response_type=code&redirect_uri=REDIRECT_URI
#   - OAuth Token: https://login.live.com/oauth20_token.srf


# Drive Api - url starting with    https://apis.live.net/v5.0
# - permission http://msdn.microsoft.com/en-us/library/dn631840.aspx
# - folder http://msdn.microsoft.com/en-us/library/dn631836.aspx

#>
[CmdletBinding(SupportsShouldProcess=$true)]
Param(
    [parameter(Position=1, HelpMessage='AX Delploy source files')]
    [string]$SourcePath='.'
    
    ,[parameter(Mandatory=$true)]
    [string]$ClientId = "000000004C1184BB"
    
    ,[parameter(Mandatory=$true)]
    [string]$Secret = "iBQzWEfQbvOaygacoOlqAjjjPMRIXE0J"
    ,[parameter()]
    [string]$AuthCode = '4db6ccea-3067-5608-de9c-ac88f2a58e2c'
)

$RedirectUri = "https://login.live.com/oauth20_desktop.srf"
$AuthorizeUri = "https://login.live.com/oauth20_authorize.srf"
$ScopeArray = "wl.skydrive","wl.offline_access"
$Scope = $ScopeArray -join "%20"

try
{
    $r=Read-Host "Test"
}
catch
{
    $exMsg = @"
Either run script in interactive mode or pass AuthCode as argument.
Authorization Code [AuthCode] can be retrived at 
https://login.live.com/oauth20_authorize.srf?client_id=$ClientId&scope=$Scope&response_type=code&redirect_uri=$RedirectUri

"@

# https://login.live.com/oauth20_authorize.srf?client_id=000000004C1184BB&scope=wl.skydrive%20wl.offline_access&response_type=code
# https://login.live.com/oauth20_authorize.srf?client_id=000000004C1184BB&scope=wl.skydrive%20wl.offline_access&response_type=code&redirect_uri=https://login.live.com/oauth20_desktop.srf
# https://login.live.com/oauth20_authorize.srf?client_id=000000004C1184BB&scope=wl.skydrive%20wl.offline_access&response_type=code&redirect_uri=http%3A%2F%2Fmatejskubic.github.io%2Ftest-ghpages%2Ftest.html
    $ex = New-Object System.Exception $exMsg, $_.Exception
    throw $ex
}



#       https://login.live.com/oauth20_authorize.srf?client_id=CLIENT_ID&scope=SCOPES&response_type=RESPONSE_TYPE&redirect_uri=REDIRECT_URL
$url = "https://login.live.com/oauth20_authorize.srf?client_id=$ClientId&scope=$Scope&response_type=token"

$localStoragePath = Join-Path $env:LOCALAPPDATA 'Adacta\PublishAxModel.ps1'
$localStoragePathRefreshToken = Join-Path $localStoragePath RefreshToken.xml
$null = mkdir -Force $localStoragePath

$RefreshToken = ''
$AccessToken = ''

function getRefreshToken()
{
    Add-Type -AssemblyName System.Windows.Forms
    
    $OnDocumentCompleted = {
      if($web.Url.AbsoluteUri -match "code=([^&]*)") {
        $script:AuthCode = $Matches[1]
        $form.Close()
      }
      elseif($web.Url.AbsoluteUri -match "error=") {
        $form.Close()
      }
    }

    $web = new-object System.Windows.Forms.WebBrowser -Property @{Width=400;Height=500}
    $web.Add_DocumentCompleted($OnDocumentCompleted)
    $form = new-object System.Windows.Forms.Form -Property @{Width=400;Height=500}
    $form.Add_Shown({$form.Activate()})
    $form.Controls.Add($web)

    # Request Authorization Code
    $web.Navigate("$AuthorizeUri`?client_id=$ClientID&scope=$Scope&response_type=code&redirect_uri=$RedirectUri")
    $null = $form.ShowDialog()
    
    # Request AccessToken
    $Response = Invoke-RestMethod -Uri "https://login.live.com/oauth20_token.srf" -Method Post -ContentType "application/x-www-form-urlencoded" -Body "client_id=$ClientID&redirect_uri=$RedirectUri&client_secret=$Secret&code=$AuthCode&grant_type=authorization_code"

    $ValidThru = (get-date).AddSeconds([int]$Response.expires_in)
    $script:AccessToken = $Response.access_token
    $script:RefreshToken = $Response.refresh_token

    return $RefreshToken
}


function getAccessToken()
{
    if (Test-Path $localStoragePathRefreshToken -PathType Leaf)
    {
        try
        {
            $RefreshToken = Import-Clixml $localStoragePathRefreshToken
        }
        catch
        {
            # ignore error
            $RefreshToken = ''
        }
    }

    if (!$RefreshToken)
    {
        $RefreshToken = getRefreshToken
    }

    if (!$RefreshToken)
    {
        Throw ("Can't retrive refresh token")
    }

    if (!$AccessToken)
    {
        # Request AccessToken
        $Response = Invoke-RestMethod -Uri "https://login.live.com/oauth20_token.srf" -Method Post -ContentType "application/x-www-form-urlencoded" -Body "client_id=$ClientID&redirect_uri=$RedirectUri&client_secret=$Secret&refresh_token=$RefreshToken&grant_type=refresh_token"

        Write-Verbose 'Accest token response'
        Write-Verbose ($Response | Out-String)
    
        $ValidThru = (get-date).AddSeconds([int]$Response.expires_in)
        $AccessToken = $Response.access_token
        $RefreshToken = $Response.refresh_token
    }
    
    if (!$AccessToken)
    {
        Throw ("Can't retrive access token")
    }

    $RefreshToken | Export-Clixml $localStoragePathRefreshToken

    return $AccessToken
}

$AccessToken = getAccessToken

$ApiUri = "https://apis.live.net/v5.0"

$Root = Invoke-RestMethod -Uri "$ApiUri/me/skydrive?access_token=$AccessToken"

$r = Invoke-RestMethod -Uri "$($Root.upload_location)?access_token=$AccessToken"
#$r.data | Format-Table

$AxModelRoot = $r.data | Where-Object { $_.name -eq "AxModel"}
#$AxModelRoot | Format-List -Verbose

#$r = Invoke-RestMethod -Uri "$($AxModelRoot.upload_location)?access_token=$AccessToken"
#$r.data | Format-Table

$r = Invoke-RestMethod -Uri "$($AxModelRoot.upload_location)?access_token=$AccessToken"
#$r.data | Format-Table

$AxModelRoot = $r.data | Where-Object { $_.name -eq "Eles"}


$sourcePath='\\axdev-eles62\build\Builds\ELES Main Branch Build\6.2.1000.642\Application\Appl'
#$sourcePath="C:\temp\Appl"

Get-ChildItem $sourcePath | ForEach-Object {
    #Write-Verbose -Verbose '-------------------------------------'
    Write-Verbose -Verbose ('Uploading file {0}:' -f $_.FullName)
    $_.IsReadOnly = $false
    $uploadResult=Invoke-RestMethod -Uri "$($AxModelRoot.upload_location)/$($_.Name)?access_token=$AccessToken" -Method Put -InFile $_.FullName
    Write-Verbose ($uploadResult | Out-String)
}

