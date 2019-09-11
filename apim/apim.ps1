[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {
<#  
Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
This task creates a Gateway API against a backend API using the backend's swagger definition. 
Prerequisite to using this task: the API Gateway requires connectivity to the backend, so make sure these are either public, either part of a
shared VNET
#>	
	#getting inputs
	    $arm=Get-VstsInput -Name ConnectedServiceNameARM
		$Endpoint = Get-VstsEndpoint -Name $arm -Require
		$newapi=Get-VstsInput -Name targetapi
		$protocols =Get-VstsInput -Name protocols
		$newpath=Get-VstsInput -Name targetpath
		$portal=Get-VstsInput -Name ApiPortalName
		$rg=Get-VstsInput -Name ResourceGroupName 
		$swaggerlocation=Get-VstsInput -Name swaggerlocation
		$product=Get-VstsInput -Name product1 
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

	#preparing endpoints	
		$client=$Endpoint.Auth.Parameters.ServicePrincipalId
		$secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
		$tenant=$Endpoint.Auth.Parameters.TenantId		
		$body="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
        "&client_id=$($client)"+
        "&grant_type=client_credentials"+
        "&client_secret=$($secret)"
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
		$json = '{
			"properties": {
				"contentFormat": "swagger-link-json",
				"contentValue": "'+$($SwaggerLocation)+'",
				"path": "'+$($newapi)+'"
			}
		}'

		write-host $json
		$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
		#$targeturl="$($baseurl)/apis/$($newapi)?api-version=2017-03-01"
		$targeturl="$($baseurl)/apis/$($newapi)?api-version=2018-06-01-preview"
		
		Write-Host "Creating or updating API $($targeturl)"
		try
		{
			Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers -Body $json -Method Put -ContentType "application/json"
		}
		catch [System.Net.WebException] 
		{
			$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
			Write-Host $er.error.details
			throw
		}
		
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
				Write-Host $er.error.details
				throw
			}
			
		}
	#Policy content should never be null or empty. The 'none' policy will always apply if nothing is specified.
		if($PolicyContent -ne $null -and $PolicyContent -ne "")
		{
			try
			{
				$policyapiurl=	"$($baseurl)/apis/$($newapi)/policies/policy?api-version=2017-03-01"
				$JsonPolicies = "{
				  `"properties`": {					
					`"policyContent`":`""+$PolicyContent+"`"
					}
				}"
				Write-Host "Linking policy to API USING $($policyapiurl)"
				Write-Host $JsonPolicies
				Invoke-WebRequest -UseBasicParsing -Uri $policyapiurl -Headers $headers -Method Put -Body $JsonPolicies -ContentType "application/json"
			}
			catch [System.Net.WebException] 
			{
				$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
				Write-Host $er.error.details
				throw
			}
		}
#		https://management.azure.com/subscriptions/c84c870d-2541-4a67-b58f-229bf044c647/resourceGroups/Podium-Next-Development/providers/Microsoft.ApiManagement/service/podiumnextapi-dev/apis/podium-playlist-admin?api-version=2018-01-01
#		https://management.azure.com/subscriptions/c84c870d-2541-4a67-b58f-229bf044c647/resourceGroups/Podium-Next-Development/providers/Microsoft.ApiManagement/service/podiumnextapi-dev/apis/podium-playlist-admin?api-version=2018-06-01-preview
		if ($protocols -ne "http")
		{
			Write-Host "Update API to use https or both http and https"
			Write-Host "Target URL: $($targeturl)"
			if ($protocols -eq "https")
			{
				Write-Host "update api to use https only"
				$protocoljson = '{
					"properties": {
						"protocols":["https"]
					}
				}'
	
			}
			else
			{
				Write-Host "update api to use http and https"
				$protocoljson = '{
					"properties": {
						"protocols":["http","https"]
					}
				}'
			}

			try
			{
				Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers -Body $protocoljson -Method Patch -ContentType "application/json"
			}
			catch [System.Net.WebException] 
			{
				$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
				Write-Host $er.error.details
				throw
			}
		}


		Write-Host $rep

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}