[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation

try 
{
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
	Write-Host "ResourceGroup: $($ResourceGroup)"

	$ApiVersionSet = Get-VstsInput -Name ApiVersionSetName
	Write-Host "ApiVersionSet: $($ApiVersionSet)"

	$SwaggerLocation=Get-VstsInput -Name SwaggerLocation
	Write-Host "SwaggerLocation: $($SwaggerLocation)"

	$ApiVersionName = Get-VstsInput -Name ApiVersionName
	Write-Host "ApiVersionName: $($ApiVersionName)"

	$apipath = Get-VstsInput -Name ApiPath
	Write-Host "apipath: $($apipath)"

	$newapi = "$($apipath)-$($ApiVersionName)"
	Write-Host "newapi: $($newapi)"

	$Product=Get-VstsInput -Name Product
	Write-Host "Product: $($Product)"

	$UseProductCreatedByPreviousTask=Get-VstsInput -Name UseProductCreatedByPreviousTask
	Write-Host "UseVersionSetCreatedByPrevoiusTask: $($UseVersionSetCreatedByPrevoiusTask)"
	Write-Host "previous task version set: $($env:NewVersionSetId)"

	$UseVersionSetCreatedByPrevoiusTask = Get-VstsInput -Name UseVersionSetCreatedByPrevoiusTask
	Write-Host "UseVersionSetCreatedByPrevoiusTask: $($UseVersionSetCreatedByPrevoiusTask)"

	$ApiVersionSetName = Get-VstsInput -Name ApiVersionSetName
	Write-Host "ApiVersionSetName: $($ApiVersionSetName)"

	#preparing endpoints	
	Write-Host "Prepare endpoints"
	$client=$Endpoint.Auth.Parameters.ServicePrincipalId
	$secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
	$tenant=$Endpoint.Auth.Parameters.TenantId		
	$body="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
	"&client_id=$($client)"+
	"&grant_type=client_credentials"+
	"&client_secret=$($secret)"

	Write-Host "Getting authorization content"

	try
	{
		#getting ARM token
		$resp=Invoke-WebRequest -UseBasicParsing -Uri "https://login.windows.net/$($tenant)/oauth2/token" `
		-Method POST `
		-Body $body| ConvertFrom-Json    

	}
	catch [System.Net.WebException] 
	{
		$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
		write-host $er.error.details
		throw
	}

	$headers = @{
	Authorization = "Bearer $($resp.access_token)"        
	}

	$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($ResourceGroup)/providers/Microsoft.ApiManagement/service/$($portal)"

	if($UseVersionSetCreatedByPrevoiusTask -eq $true)
	{
		Write-Host "Use an api-version-set create from previous task"
		$versionset = $env:NewVersionSetId
		if($versionset -eq $null -or $versionset -eq "")
		{
			throw "There was no version set created by a previous task"
		}
		else 
		{
			Write-Host "Use existing API Version Set name: $($versionset)"
			#checking if target api-version-set already exists
			try 
			{				
				$VersionSetUrl="$($Endpoint.Url)$($versionset)?api-version=2018-01-01"
				Write-Output "checking whether $($versionset) exists"
				$ApiExistsResponse=Invoke-WebRequest -UseBasicParsing -Uri $VersionSetUrl -Headers $Headers | ConvertFrom-Json
				$versionset=$ApiExistsResponse.id
				$ApiExists=$True
			}
			catch
			{
				throw "Version set not found"

			}
		}
# TODO : path should be the version-set-name and be exposed from previus step
# TODO: Remove feature to choose version set from release step (will require a previous step.)
		Write-Host "Construct json bodys"
		$json = '{ "properties": {
			"contentFormat": "swagger-link-json",
			"contentValue": "'+$($SwaggerLocation)+'",
			"path": "'+$($newapi)+'",
			"protocols":["https"]}}'
		write-host $json

		$targeturl="$($baseurl)/apis/$($newapi)?api-version=2018-01-01"

		Write-Host "Creating or updating API $($targeturl)"
		try
		{
			Write-Host "Create the initial API"
			Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers -Body $json -Method Put -ContentType "application/json"

			$json = '{ "properties": {
				"apiVersion": "'+$($ApiVersionName)+'",
				"apiVersionSetId": "' + $($versionset) +'"}}'

				Write-Host "Attach api version set to api"
				Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers -Body $json -Method Patch -ContentType "application/json"

			if($UseProductCreatedByPreviousTask -eq $true)
			{
				$product = $env:NewUpdatedProduct
				if($product -eq $null -or $product -eq "")
				{
					throw "There was no product created by a previous task"
				}
			}
			if($product -ne $null -and $product -ne "")
			{
				$productapiurl=	"$($baseurl)/products/$($product)/apis/$($newapi)?api-version=2017-03-01"
				
				try
				{
					Write-Host "Linking API to product $($productapiurl)"
					Invoke-WebRequest -UseBasicParsing -Uri $productapiurl -Headers $headers -Method Put 
				}
				catch [System.Net.WebException] 
				{
					$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
					Write-Hosts $er.error.details
					throw
				}
				
			}
		}
		catch [System.Net.WebException] 
		{
			$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
			Write-Host $er.error.details
			throw
		}
	}
	Write-Host $rep
} 
finally {
    Trace-VstsLeavingInvocation $MyInvocation
}

