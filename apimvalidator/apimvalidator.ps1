[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
<#  
Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
This task creates a Gateway API against a backend API using the backend's swagger definition. 
Prerequisite to using this task: the API Gateway requires connectivity to the backend, so make sure these are either public, either part of a
shared VNET
#>
# npm install -g swagger-cli
# tfx extension create --manifest-globs vss-extension.json

try {
	$swaggerlocation=Get-VstsInput -Name swaggerlocation
	$p = Invoke-Expression "npm config get prefix"
	Invoke-Expression "npm install -g swagger-cli"
	$match = Invoke-Expression "cmd /c $($p)\swagger-cli validate $($swaggerlocation)"
    if ($match)
    {
    	if ($match -match "$($swaggerlocation) is valid")
	    {
		    Write-Host "The swagger document is valid"
	    }
	    else
	    {
		    Write-Host "The Swagger document is not valid"
		    Write-Host $match
            throw "$($swaggerlocation) is not a valid OpenAPI 3.0 or Swagger 2.0 document"


	    }
    }
    else
    {
        throw "$($swaggerlocation) is not a valid OpenAPI 3.0 or Swagger 2.0 document"
    }

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}