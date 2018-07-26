# NOTICE!!!
This Extention to VSTS is a fork of Stephane Eyskens "API Management Suite" (https://marketplace.visualstudio.com/items?itemName=stephane-eyskens.apim). 

# Disclaimer
This software is provided as-is with no warranty of any kind. 
# API Management Suite in a nutshell
The purpose of this extension is to bring Azure API Management into VSTS as part of your release lifecyle. Whether you use API Management to monetize APIS or for internal purposes, it
is good to associate the release of your backends APIs with their corresponding facade APIs published against the API Gateway. On top of the API Management integration, the extension also 
ships with an API Security Checker that helps validating that all endpoints of an API are well secured, this is of course only applicable to non-public APIs.
This forked version intends to solve some gaps in the existing 
# Release Notes
## v1.2.4
* Fixed typo in apim import script
* Updated to azure rest api version 2018-06-01-preview
## v1.2.1
* Forked version of https://github.com/stephaneey/azure-apim-extension
* Renamed extention to avoid naming confusion
* Changed extention icons
* Added release task for checking validity of Swagger 2.0 / OpenAPI 3.0 document
* Added more required properties to api importer

# Setup prerequisite and considerations
In order to use this extension, you must have an ARM Service Endpoint configured in VSTS and make sure this endpoint is allowed to contribute to API Management instances. This can easily 
be done by granting Subscription Contributor role or the ad-hoc API Management Service Contributor role. Similarly, the endpoint should  have access to the Azure Functions.

Depending of your usage of API Management, some extra considerations should also be paid attention to. If your backend APIs are part of a dedicated VNET, make sure the VSTS agents have connectivity to them. The extension makes use of Swagger import and downloads the Swagger definition of the backend API. Therefore, connectivity between the VSTS agent and the target API is required.
# Policies
A few tasks allow to set policies at product and/or API level. The task ships with some pre-defined policies which one can override to adjust them to specific needs. You can easily use other policies by getting the default boilerplate config from the APIM Portal.
# Tasks included in the extension
## Azure APIM - Product
This task allows you to create a new product or update an existing one.
## Azure APIM - OpenAPI import, create or update
This task allows you to create a new Gateway API or update an existing one, against backend APIs. 
## Azure APIM - OpenAPI import or update Versioned API
This task allows you to create a new Versioned Gateway API or update an existing one, against backend APIs. The reason why versioning has been put in a separate task is to make it clear for the VSTS Release Managers. 
## Azure APIM - Create or Update from Azure Functions
This task allows you to create a new Gateway API or update an existing one, against Azure Functions that are protected with a code in the Function URL. For each and every function, a corresponding API Operation is created with a specific policy that injects the function's secret as a querystring parameter.
## Azure APIM - Create or Update versioned API on Azure Functions
Same as above but in a versioned way.
## Azure APIM Security Checker
This very basic task parses the Swagger definition of an API (or MVC apps) to check whether all the exposed endpoints are secured. Every return code that differs from 401 or 302 (redirection to the login page) are marked unsafe. If at least one unsafe endpoint is discovered, the task fails to complete and all the tested endpoints appear in the logs.
## Azure APIM - Validate API definition
Takes an public link to a Swagger 2.0 or OpenAPI 3.0 api definition and validates it.
