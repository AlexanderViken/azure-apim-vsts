[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {

<#
Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
This task creates a versioned Gateway API against a backend API using the backend's swagger definition.
Prerequisite to using this task: the API Gateway requires connectivity to the backend, so make sure these are either public, either part of a
shared VNET
#>

	    $ConnectedServiceNameARM=Get-VstsInput -Name ConnectedServiceNameARM
		$Endpoint=Get-VstsEndpoint -Name $ConnectedServiceNameARM -Require
		$TargetApi=Get-VstsInput -Name TargetApi
		if($TargetApi.startswith("/subscriptions"))
		{
			$TargetApi=$TargetApi.substring($TargetApi.indexOf("/apis")+6)
		}
		$TargetApiVersion=Get-VstsInput -Name TargetApiVersion
		$Portal=Get-VstsInput -Name ApiPortalName
		$ResourceGroup=Get-VstsInput -Name ResourceGroupName
		$ApiVersionSet = Get-VstsInput -Name ApiVersionSetName
		$SwaggerLocation=Get-VstsInput -Name SwaggerLocation
		$Product=Get-VstsInput -Name Product
		$UseProductCreatedByPreviousTask=Get-VstsInput -Name UseProductCreatedByPreviousTask
		$SelectedTemplate=Get-VstsInput -Name TemplateSelector
		if($SelectedTemplate -eq "CacheLookup")
		{
			$PolicyContent = Get-VstsInput -Name CacheLookup
		}
		if($SelectedTemplate -eq "CORS")
		{
			$PolicyContent = Get-VstsInput -Name CORS
		}
		if($SelectedTemplate -eq "None")
		{
			$PolicyContent = Get-VstsInput -Name None
		}
		if($SelectedTemplate -eq "Basic")
		{
			$PolicyContent = Get-VstsInput -Name Basic
		}
		if($SelectedTemplate -eq "IP")
		{
			$PolicyContent = Get-VstsInput -Name IP
		}
		if($SelectedTemplate -eq "RateByKey")
		{
			$PolicyContent = Get-VstsInput -Name RateByKey
		}
		if($SelectedTemplate -eq "QuotaByKey")
		{
			$PolicyContent = Get-VstsInput -Name QuotaByKey
		}
		if($SelectedTemplate -eq "HeaderCheck")
		{
			$PolicyContent = Get-VstsInput -Name HeaderCheck
		}
		if($PolicyContent -ne $null -and $PolicyContent -ne "")
		{
			$PolicyContent = $PolicyContent.replace("`"","`'")
		}

		$ClientId=$Endpoint.Auth.Parameters.ServicePrincipalId
		$Secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
		$TenantId=$Endpoint.Auth.Parameters.TenantId
		$GetTokenBody="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
        "&client_id=$($ClientId)"+
        "&grant_type=client_credentials"+
        "&client_secret=$($Secret)"
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

		$BaseUrl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($ResourceGroup)/providers/Microsoft.ApiManagement/service/$($Portal)"
		$TargetUrl="$($BaseUrl)/apis/$($TargetApi)?api-version=2018-06-01-preview"
		#checking whether the API already exists or not. If not, a versionset must be created.
		try
		{
			Write-Output "checking whether $($TargetUrl) exists"
			$ApiExistsResponse=Invoke-WebRequest -UseBasicParsing -Uri $TargetUrl -Headers $Headers|ConvertFrom-Json
			$CurrentApiVersion=$ApiExistsResponse.properties.apiVersion
			$ApiExists=$true
			Write-Output "Found existing $($TargetApi)"
		}
		catch [System.Net.WebException]
		{
			if($_.Exception.Response.StatusCode -eq "NotFound")
            {
				$ApiExists=$false
			}
            else
            {
			    throw
            }
		}

		try
		{
			#downloading swagger for later import
			$HttpClient=[System.Net.WebClient]::new()
			$SwaggerContent=$HttpClient.DownloadString($SwaggerLocation)
			$HttpClient.Dispose()

			if($ApiExists -eq $false)
			{
				Write-Output "Creating new API from scratch"
				#creating the api version set, the api and importing the swagger definition into it
				$VersionSetId="$($TargetApi)$($TargetApiVersion)"
				$VersionSetUrl="$($BaseUrl)/api-version-sets/$($VersionSetId)?api-version=2017-03-01"
				$CreateVersionSetBody='{
					"id":"/api-version-sets/'+$($VersionSetId)+'",
					"name":"'+$($TargetApi)+'",
					"properties":{
						"displayName": "'+$($TargetApi)+'",
						"versioningScheme": "Query",
						"versionQueryName": "version",
						"isCurrent":true
					}
				}'
				Write-Output "Creating version set using $($VersionSetUrl) using $($CreateVersionSetBody)"
				$Headers.Add("If-Match","*")
				Invoke-WebRequest -UseBasicParsing -Uri $VersionSetUrl  -Body $CreateVersionSetBody -ContentType "application/json" -Headers $Headers -Method Put
				
				$TargetApiUrl="$($BaseUrl)/apis/$($TargetApi)?api-version=2017-03-01"
				$CreateApiBody = '{
					"id":"/apis/'+$($TargetApi)+'",
					"name":"'+$($TargetApi)+'",
					"properties":
					{
						"displayName":"'+$($TargetApi)+'",
						"path":"'+$($TargetApi)+'",
						"protocols":["https"],
						"apiVersion":"'+$($TargetApiVersion)+'",
						"apiVersionSet":{
							"id":"/api-version-sets/'+$($VersionSetId)+'",
							"name":"'+$($TargetApi)+'",
							"versionQueryName":"version",
							"versioningScheme":"Query"
						},
						"apiVersionSetId":"/api-version-sets/'+$VersionSetId+'"
				  	}
				}'
				Write-Output "Creating API using $($TargetApiUrl) and $($CreateApiBody)"
				Invoke-WebRequest -UseBasicParsing -Uri $TargetApiUrl  -Body $CreateApiBody -ContentType "application/json" -Headers $Headers -Method Put
				
				$ImportSwaggerContent="$($BaseUrl)/apis/$($TargetApi)?import=true&api-version=2017-03-01"

				Write-Output "Importing Swagger definition to API using $($ImportSwaggerContent)"
				Invoke-WebRequest -UseBasicParsing $ImportSwaggerContent -Method Put -ContentType "application/vnd.swagger.doc+json" -Body $SwaggerContent -Headers $Headers
			}
			else
			{
				$ApiVersionExists=$false
				#the api already exists, only a new version must be created.
				$ApiVersionUrl="$($BaseUrl)/apis/$($TargetApi)$($TargetApiVersion)?api-version=2018-06-01-preview"
				try
				{
					Invoke-WebRequest -UseBasicParsing -Uri $ApiVersionUrl -Headers $Headers -Method Head
					$ApiVersionExists=$true
				}
				catch [System.Net.WebException]
				{
					if($_.Exception.Response.StatusCode -eq "NotFound")
					{
						Write-Output "Version not found at $($ApiVersionUrl))"
						$ApiVersionExists=$false
					}
					else
					{
						throw
					}
				}
				Write-Output "Current version $($CurrentApiVersion), version is $($TargetApiVersion), version exists $($ApiVersionExists)"
				
				$ApiVersionBody='{
					"sourceApiId":"/apis/'+$($TargetApi)+'",
					"apiVersionName":"'+$($TargetApiVersion)+'",
					"apiVersionSet":{
						"versioningScheme": "Query",
						"versionQueryName": "version",
						"isCurrent":true
					}
				}'
				if($CurrentApiVersion -ne $TargetApiVersion -and $ApiVersionExists -eq $false)
				{
					$NewApiVersionUrl="$($BaseUrl)/apis/$($TargetApi)$($TargetApiVersion);rev=1?api-version=2018-06-01-preview"
					Write-Output "Creating a new version $($NewApiVersionUrl) with $($ApiVersionBody)"
					Invoke-WebRequest -UseBasicParsing $NewApiVersionUrl -Method Put -ContentType "application/vnd.ms-azure-apim.revisioninfo+json" -Body $ApiVersionBody -Headers $Headers
				}
					
				$ImportSwaggerContent="$($BaseUrl)/apis/$($TargetApi)$($TargetApiVersion)?import=true&api-version=2018-06-01-preview"
				$Headers.Add("If-Match","*")
				Write-Output "Importing swagger $($ImportSwaggerContent)"
				Invoke-WebRequest -UseBasicParsing $ImportSwaggerContent -Method Put -ContentType "application/vnd.swagger.doc+json" -Body $SwaggerContent -Headers $Headers
			}

		}
		catch [System.Net.WebException]
		{
			$ExceptionMessage=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
			Write-Output $ExceptionMessage.error.details
			throw
		}

		if($UseProductCreatedByPreviousTask -eq $true)
		{
			$Product = $env:NewUpdatedProduct
			if($Product -eq $null -or $Product -eq "")
			{
				throw "There was no product created by a previous task"
			}
		}
		if($NewApiVersionUrl -eq $null -or $NewApiVersionUrl -eq "" -or ($CurrentApiVersion -eq $TargetApiVersion))
		{
			$apimv="$($TargetApi)"
		}
		else
		{
			$apimv="$($TargetApi)$($TargetApiVersion)"
		}
		if($Product -ne $null -and $Product -ne "")
		{
			$ProductApiUrl=	"$($BaseUrl)/products/$($Product)/apis/$($apimv)?api-version=2017-03-01"

			try
			{
				Write-Output "Linking API to product $($ProductApiUrl)"
				Invoke-WebRequest -UseBasicParsing -Uri $ProductApiUrl -Headers $Headers -Method Put
			}
			catch [System.Net.WebException]
			{
				$ExceptionMessage=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
				Write-Output $ExceptionMessage.error.details
				throw
			}

		}
		if($PolicyContent -ne $null -and $PolicyContent -ne "")
		{
			try
			{
				$policyapiurl=	"$($BaseUrl)/apis/$($apimv)/policies/policy?api-version=2017-03-01"
				$JsonPolicies = "{
				  `"properties`": {
					`"policyContent`":`""+$PolicyContent+"`"
					}
				}"
				Write-Output "Linking policy to API USING $($policyapiurl)"
				Write-Output $JsonPolicies
				Invoke-WebRequest -UseBasicParsing -Uri $policyapiurl -Headers $Headers -Method Put -Body $JsonPolicies -ContentType "application/json"
			}
			catch [System.Net.WebException]
			{
				$ExceptionMessage=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
				Write-Output $ExceptionMessage.error.details
				throw
			}
		}
		Write-Output $rep

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}