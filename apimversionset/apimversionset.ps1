[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {
    # variables from ui
    $ConnectedServiceNameARM=Get-VstsInput -Name ConnectedServiceNameARM
    $Endpoint=Get-VstsEndpoint -Name $ConnectedServiceNameARM -Require
    $Portal=Get-VstsInput -Name ApiPortalName
    $ResourceGroup=Get-VstsInput -Name ResourceGroupName
    $SwaggerLocation=Get-VstsInput -Name SwaggerLocation
    $ApiVersionSetName = Get-VstsInput -Name ApiVersionSetName
    $ApiVersionSetDescription = Get-VstsInput -Name ApiVersionSetDescription
    $ApiVersionSetDisplayName = Get-VstsInput -Name ApiVersionSetDisplayName

    $ClientId=$Endpoint.Auth.Parameters.ServicePrincipalId
    $Secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
    $TenantId=$Endpoint.Auth.Parameters.TenantId
    $GetTokenBody="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
    "&client_id=$($ClientId)"+
    "&grant_type=client_credentials"+
    "&client_secret=$($Secret)"

    # Get bearer token for the api calls
    try
    {
        $resp=Invoke-WebRequest -UseBasicParsing -Uri "https://login.windows.net/$($TenantId)/oauth2/token" `
            -Method POST `
            -Body $GetTokenBody|ConvertFrom-Json

    }
    catch [System.Net.WebException]
    {
        $ExceptionMessage=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
        Write-Output $ExceptionMessage.error.details
        throw
    }
    $Headers = @{
        Authorization = "Bearer $($resp.access_token)"
    }

    # setting base url for all apim calls to azure
    $BaseUrl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($ResourceGroup)/providers/Microsoft.ApiManagement/service/$($Portal)"

    $VersionSetUrl="$($BaseUrl)/api-version-sets/$($ApiVersionSetName)?api-version=2018-01-01"

    #checking if target api-version-set already exists
    try {
        Write-Output "checking whether $($ApiVersionSetName) exists"
        $ApiExistsResponse=Invoke-WebRequest -UseBasicParsing -Uri $VersionSetUrl -Headers $Headers | ConvertFrom-Json
        $CurrentApiVersionSetId=$ApiExistsResponse.id
        $ApiExists=$True
    }
    catch
    {
        if($_.Exception.Response.StatusCode -eq "NotFound")
        {
            $ApiExists=$False
        }
        else
        {
            throw
        }
    }

    if ($ApiExists -eq $True)
    {
        Write-Host "The api-version-set already exists"
        #Set env variable so it can be fetched in next step(s)
        Write-Host ("##vso[task.setvariable variable=NewVersionSetId;]$CurrentApiVersionSetId")
        Write-Host ("##vso[task.setvariable variable=NewVersionUrlPrefix;]$ApiVersionSetName")

    }
    else
    {
        Write-Host "Need to create a new API Version Set"
        $postBody = '{
            "name": "' + $ApiVersionSetName + '",
            "properties": {
              "displayName": "' + $ApiVersionSetDisplayName + '",
              "description": "' + $ApiVersionSetDescription + '",
              "versioningScheme": "Query",
              "versionQueryName": "version",
              "versionHeaderName": null
            }
          }'
          try {
            $createResponse = Invoke-WebRequest -UseBasicParsing -Uri $VersionSetUrl -Headers $headers -Method Put -Body $postBody -ContentType "application/json" | ConvertFrom-Json
            $CurrentApiVersionSetId=$createResponse.id

            #Set env variable so it can be fetched in next step(s)
            Write-Host ("##vso[task.setvariable variable=NewVersionSetId;]$CurrentApiVersionSetId")
            Write-Host ("##vso[task.setvariable variable=NewVersionUrlPrefix;]$ApiVersionSetName")
          }
          catch {
                Write-Host $_.Exception.Response.StatusCode
          }
    }
}
finally {
    Trace-VstsLeavingInvocation $MyInvocation
}