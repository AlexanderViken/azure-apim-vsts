[CmdletBinding()]
param()

function LogException
{
	param ([System.Exception] $e)

	$exception = $e
	Write-Host "Convert exception to json: " 
	Write-Host $($exception | ConvertTo-Json)
	
	# $msg = $exception.Message
	# while ($exception.InnerException) {
	# 	  $exception = $exception.InnerException
	# 	  $msg += "`n" + $exception.Message
	# }

	# Write-Host "Exception messages: " $msg
}

Trace-VstsEnteringInvocation $MyInvocation
try 
{        
	<#  
	Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
	This task creates a Gateway API against an Azure Function set.
	Prerequisite to using this task: VSTS agents must be able to connect to both the functions & APIM through ARM.
	#>

	$arm=Get-VstsInput -Name ConnectedServiceNameARM
	$Endpoint = Get-VstsEndpoint -Name $arm -Require	
	$newapisuffix=Get-VstsInput -Name targetapi	
	if($null -ne $newapisuffix -and $newapisuffix.indexOf("/apis/")-ne -1)
	{
		$newapisuffix=$newapisuffix.Substring($newapisuffix.indexOf("/apis")+6)
	}
	$v=Get-VstsInput -Name version
	$portal=Get-VstsInput -Name ApiPortalName
	$rg=Get-VstsInput -Name APIResourceGroupName 
	$functiongroup=Get-VstsInput -Name ResourceGroupName 		
	$functionsite=Get-VstsInput -Name HostingWebSite
	$product=Get-VstsInput -Name product1 
	
	$client=$Endpoint.Auth.Parameters.ServicePrincipalId
	$secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
	$tenant=$Endpoint.Auth.Parameters.TenantId		
	$body="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
    	  "&client_id=$($client)"+
          "&grant_type=client_credentials"+
          "&client_secret=$($secret)"
	try
	{
		$resp=Invoke-WebRequest -UseBasicParsing -Uri "https://login.windows.net/$($tenant)/oauth2/token" `
			-Method POST `
			-Body $body| ConvertFrom-Json    
	}
	catch [System.Exception] 
	{
		$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
		write-host $er.error.details
		throw
	}
		
	$headers = @{
		Authorization = "Bearer $($resp.access_token)"        
	}
	
	$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
	$functionbaseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($functiongroup)/providers/Microsoft.Web/sites/$($functionsite)"
	$versionSet="$($newapisuffix)"
	$finalApi=$functionsite

	$apiurl="$($baseurl)/apis/$($functionsite)?api-version=2019-01-01"
	$apiexist=$false
	try
	{			
		$apiExistsResponse=Invoke-WebRequest -UseBasicParsing -Uri $apiurl -Headers $headers|ConvertFrom-Json
		$currentApiVersion=$apiExistsResponse.properties.apiVersion
		$apiexist=$true
	}
	catch [System.Net.WebException] 
	{
		if($_.Exception.Response.StatusCode -eq "NotFound")
        {
			$apiexist=$false
		}
	}

	if($apiexist -eq $false)
	{
		Write-Host "Creating new API version set from scratch"
		$Headers.Add("If-Match","*")
		$versionseturl="$($baseurl)/apiVersionSets/$($versionSet)?api-version=2019-01-01"
		$body='{"id": "/apiVersionSets/'+$($versionSet)+'","properties": {"displayName": "'+$($versionSet)+'","versioningScheme": "Segment"}}'
		Write-Host $body
		try 
		{
			Invoke-WebRequest -UseBasicParsing -Uri $versionseturl -Body $body -ContentType "application/json" -Headers $headers -Method Put
		}
		catch [System.Net.WebException] 
		{
			LogException($_.Exception)
			throw
		}

		$apiurl="$($baseurl)/apis/$($finalApi)?api-version=2019-01-01"
		$body='{
				"id": "/apis/'+$($finalApi)+'",
				"name": "'+$($functionsite)+'",
				"properties": {
					"displayName": "'+$($functionsite)+'",
					"protocols": [ "https" ],
					"description": "Import from \"'+$($functionsite)+'\" Function App",
					"path": "'+$($newapisuffix)+'",
					"apiVersion": "'+$($v)+'",
					"apiVersionSetId": "/apiVersionSets/'+$($versionSet)+'",
					"apiVersionSet": {
						"name": "'+$($versionSet)+'",
						"versioningScheme": "Segment"
					}
				}
			}'
		Write-Host "Creating API using $($finalApi) with body: $($body)"		
		try 
		{
			Invoke-WebRequest -UseBasicParsing -Uri $apiurl  -Body $body -ContentType "application/json" -Headers $headers -Method Put
		}
		catch [System.Exception] 
		{
			LogException($_.Exception)
			throw
		}
	}
	else {
		$ApiVersionExists=$false
		$ApiVersionUrl="$($BaseUrl)/apiVersionSets/$($versionSet)?api-version=2019-01-01"
		try
		{
			Invoke-WebRequest -UseBasicParsing -Uri $ApiVersionUrl -Headers $Headers -Method Head
			$ApiVersionExists=$true
		}
		catch [System.Net.WebException]
		{
			if($_.Exception.Response.StatusCode -eq "NotFound")
			{
				$ApiVersionExists=$false
			}
			else
			{
				LogException($_.Exception)
				throw
			}
		}
		Write-Output "Current version $($currentApiVersion), version is $($v), version exists $($ApiVersionExists)"
		
		if($CurrentApiVersion -ne $v -and $ApiVersionExists -eq $false)
		{
			$ApiVersionBody='{
				"sourceApiId":"/apis/'+$($functionsite)+'",
				"apiVersionName":"'+$($v)+'",
				"apiVersionSet":{
					"name": "'+$($versionSet)+'",
					"versioningScheme": "Segment",
					"isCurrent":true
				}
			}'
			$finalApi="$($functionsite)$($v)"
			$NewApiVersionUrl="$($BaseUrl)/apis/$($finalApi)$;rev=1?api-version=2019-01-01"
			Write-Output "Creating a new version $($NewApiVersionUrl) with $($ApiVersionBody)"
			try 
			{
				Invoke-WebRequest -UseBasicParsing $NewApiVersionUrl -Method Put -ContentType "application/vnd.ms-azure-apim.revisioninfo+json" -Body $ApiVersionBody -Headers $Headers
			}
			catch [System.Exception] 
			{
				LogException($_.Exception)
				throw
			}
		}
	}
	
	$batchrequesturl="https://management.azure.com/batch?api-version=2016-07-01"
	$body='{
  	"requests": [{
	  "httpMethod": "PUT",
	  "relativeUrl": "/subscriptions/'+$Endpoint.Data.SubscriptionId+'/resourceGroups/'+$rg+'/providers/Microsoft.ApiManagement/service/'+$portal+'/products/'+$product+'/apis/'+$finalApi+'?api-version=2019-01-01"
    }]
	}'
	Write-Host "Linking product: $($product) with API with $($finalApi)"
	try 
	{
		Invoke-WebRequest -UseBasicParsing -Uri $batchrequesturl -Body $body -ContentType "application/json" -Headers $headers -Method Post
	}
	catch [System.Exception] 
	{
		LogException($_.Exception)
		throw
	}

	$functionsurl="$($functionbaseurl)/functions?api-version=2016-08-01"
	$functionsresp=""
	try
	{
		$functionsresp=Invoke-WebRequest -UseBasicParsing -Uri $functionsurl -Headers $headers
	}
	catch [System.Exception] 
	{
		LogException($_.Exception)
		throw
	}

	$newkeyname="apim-$($portal)-function-$($functionsite)"
	try {
		$listkeysurl="$($functionbaseurl)/host/default/listkeys?api-version=2016-08-01"
		$listkeysresp=Invoke-WebRequest -UseBasicParsing -Uri $listkeysurl -Headers $headers -Method Post
		$newkey=$listkeysresp | ConvertFrom-Json | Select-Object  -ExpandProperty "$($newkeyname)"
	}
	catch {
		$newkey="$($newkeyname)-$(New-Guid)"
	}
	$newkeyurl="$($functionbaseurl)/host/default/functionkeys/$($newkeyname)?api-version=2016-08-01"
	$body='{
		"properties": {
		  "value": "'+$($newkey)+'"
		}
	  }'
	try
	{
		Invoke-WebRequest -UseBasicParsing -Uri $newkeyurl -Body $body -ContentType "application/json" -Headers $headers -Method Put
	}
	catch [System.Exception] 
	{
		LogException($_.Exception)
		throw
	}
	
	$putkeysurl="$($baseurl)/properties/$($newkeyname)?api-version=2019-01-01"
	$body='{
		"id": "/properties/'+$newkeyname+'",
		"name": "'+$newkeyname+'",
		"properties": {
			"displayName": "'+$newkeyname+'",
			"value": "'+$($newkey)+'",
			"tags": [
				"key",
				"function",
				"auto"
			],
			"secret": true
		}
	}'
	Write-Host "Creating functions key using $($putkeysurl)"
	try
	{
		Invoke-WebRequest -UseBasicParsing -Uri $putkeysurl -Body $body -ContentType "application/json" -Headers $headers -Method Put
	}
	catch [System.Exception] 
	{
		LogException($_.Exception)
		throw
	}
	
	$body='{
	  "requests": [
		{
		  "httpMethod": "PUT",
		  "relativeUrl": "/subscriptions/'+$Endpoint.Data.SubscriptionId+'/resourceGroups/'+$rg+'/providers/Microsoft.ApiManagement/service/'+$portal+'/backends/'+$finalApi+'?api-version=2019-01-01",
		  "content": {
			"id": "'+$functionsite+'",
			"name": "'+$functionsite+'",
			"properties": {
			  "description": "'+$functionsite+'",
			  "url": "https://'+$functionsite+'.azurewebsites.net/api",
			  "protocol": "http",
			  "resourceId": "'+$functionbaseurl+'",
			  "credentials": {
				"header": {
				  "x-functions-key": [
					"{{'+$newkeyname+'}}"
				  ]
				}
			  }
			}
		  }
		},
		{
		  "httpMethod": "GET",
		  "relativeUrl": "/subscriptions/'+$Endpoint.Data.SubscriptionId+'/resourceGroups/'+$rg+'/providers/Microsoft.ApiManagement/service/'+$portal+'/apis/'+$finalApi+'/operations?api-version=2019-01-01"
		}
	  ]
	}'
	Write-Host "Creating backend for $($finalApi)"
	$batchrequesturl="https://management.azure.com/batch?api-version=2016-07-01"
	try
	{
		Invoke-WebRequest -UseBasicParsing -Uri $batchrequesturl -Body $body -ContentType "application/json" -Headers $headers -Method Post
	}
	catch [System.Exception] 
	{
		LogException($_.Exception)
		throw
	}

	$operations=@()
	$operationNames=@()
	$functionsjson = $functionsresp | ConvertFrom-Json	
	foreach($function in $functionsjson.value)
	{ 
		$httpTriggers=$function.properties.config.bindings | Where-Object { $_.type -eq "httpTrigger" }
		if($httpTriggers)
		{
			foreach($httpMethod in $httpTriggers.methods)
			{
				$functionName=$function.properties.name
				$operation=$httpMethod+'-'+$functionName
				$operationNames += $operation
				$operationjson='{
					"httpMethod": "PUT",								   
					"relativeUrl": "/subscriptions/'+$Endpoint.Data.SubscriptionId+'/resourceGroups/'+$rg+'/providers/Microsoft.ApiManagement/service/'+$portal+'/apis/'+$finalApi+'/operations/'+$operation+'?api-version=2019-01-01",
					"content":{
					    "id": "/apis/'+$finalApi+'/operations/'+$operation+'",
					    "name": "'+$operation+'",
					    "properties": {
						    "displayName": "'+$functionName+'",
						    "description": "",
							"urlTemplate": "/'+$functionName+'",
							"method": "'+$httpMethod+'",
							"templateParameters": [],
							"responses": []
					    }
					}
				}'
				$operations += $operationjson
			}
		}
	}

	$body='{
    	"requests": [
    	'
	for($i=0;$i -lt $operations.Length-1; $i++)
	{
    	$body="$($body)$($operations[$i]),
    	"
	}
	$body="$($body)$($operations[$operations.Length-1])]
	}"
	$batchrequesturl="https://management.azure.com/batch?api-version=2016-07-01"
	Write-Host "Creating API signature based on azure functions"
	try
	{
		Invoke-WebRequest -UseBasicParsing -Uri $batchrequesturl -Body $body -ContentType "application/json" -Headers $headers -Method Post		
	}
	catch [System.Exception] 
	{
		LogException($_.Exception)
		throw
	}

	$body='{
		"requests": ['
	for($i=0; $i -lt $operationNames.Length-1; $i++)
	{
		$body+='		{
			"httpMethod": "PUT",
			"relativeUrl": "/subscriptions/'+$Endpoint.Data.SubscriptionId+'/resourceGroups/'+$rg+'/providers/Microsoft.ApiManagement/service/'+$portal+'/apis/'+$finalApi+'/operations/'+$operationNames[$i]+'/policies/policy?api-version=2019-01-01",
			"content": {
				"properties": {
					"format": "rawxml",
					"value": "<policies>\n    <inbound>\n        <base />\n        <set-backend-service id=\"apim-generated-policy\" backend-id=\"'+$finalApi+'\" />\n    </inbound>\n    <backend>\n        <base />\n    </backend>\n    <outbound>\n        <base />\n    </outbound>\n    <on-error>\n        <base />\n    </on-error>\n</policies>"
				}
			}
		},'
	}
	$body+='		{
		"httpMethod": "PUT",
		"relativeUrl": "/subscriptions/'+$Endpoint.Data.SubscriptionId+'/resourceGroups/'+$rg+'/providers/Microsoft.ApiManagement/service/'+$portal+'/apis/'+$finalApi+'/operations/'+$operationNames[$i]+'/policies/policy?api-version=2019-01-01",
		"content": {
			"properties": {
				"format": "rawxml",
				"value": "<policies>\n    <inbound>\n        <base />\n        <set-backend-service id=\"apim-generated-policy\" backend-id=\"'+$finalApi+'\" />\n    </inbound>\n    <backend>\n        <base />\n    </backend>\n    <outbound>\n        <base />\n    </outbound>\n    <on-error>\n        <base />\n    </on-error>\n</policies>"
			}
		}
	}]
}'
	$batchrequesturl="https://management.azure.com/batch?api-version=2016-07-01"
	Write-Host "Adding base policy"
	try
	{
		Invoke-WebRequest -UseBasicParsing -Uri $batchrequesturl -Body $body -ContentType "application/json" -Headers $headers -Method Post
	}
	catch [System.Exception] 
	{
		LogException($_.Exception)
		throw
	}

}
finally
{
    Trace-VstsLeavingInvocation $MyInvocation
}