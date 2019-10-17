// Copyright (c)  WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file   except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/config;
import ballerina/runtime;

// Pre Authentication filter

public type PreAuthnFilter object {

    public function filterRequest(http:Caller caller, http:Request request, @tainted http:FilterContext context)
                        returns boolean {
        //Setting UUID
        int startingTime = getCurrentTime();
        context.attributes[REQUEST_TIME] = startingTime;
        checkOrSetMessageID(context);
        setHostHeaderToFilterContext(request, context);
        setLatency(startingTime, context, SECURITY_LATENCY_AUTHN);
        return doAuthnFilterRequest(caller, request, <@untainted>context);
    }

    public function filterResponse(http:Response response, http:FilterContext context) returns boolean {
        if(response.statusCode == 401) {
            sendErrorResponseFromInvocationContext(response);
        }
        return true;
    }
};

function doAuthnFilterRequest(http:Caller caller, http:Request request, http:FilterContext context)
             returns boolean {
    boolean isOauth2Enabled = false;
    runtime:InvocationContext invocationContext = runtime:getInvocationContext();
    invocationContext.attributes[MESSAGE_ID] = <string>context.attributes[MESSAGE_ID];
    printDebug(KEY_PRE_AUTHN_FILTER, "Processing request via Pre Authentication filter.");

    context.attributes[REMOTE_ADDRESS] = getClientIp(request, caller);
    context.attributes[FILTER_FAILED] = false;
    string serviceName = context.getServiceName();
    string resourceName = context.getResourceName();
    invocationContext.attributes[SERVICE_TYPE_ATTR] = context.getService();
    invocationContext.attributes[RESOURCE_NAME_ATTR] = resourceName;
    boolean isSecuredResource = isSecured(serviceName, resourceName);
    printDebug(KEY_PRE_AUTHN_FILTER, "Resource secured : " + isSecuredResource.toString());
    invocationContext.attributes[IS_SECURED] = isSecuredResource;
    context.attributes[IS_SECURED] = isSecuredResource;

    boolean isCookie = false;
    string authHeader = "";
    string? authCookie = "";
    string|error extractedToken = "";
    string authHeaderName = getAuthHeaderFromFilterContext(context);
    printDebug(KEY_PRE_AUTHN_FILTER, "Authentication header name : " + authHeaderName);
    invocationContext.attributes[AUTH_HEADER] = authHeaderName;
    string[] authProvidersIds = getAuthProviders(context.getServiceName(), context.getResourceName());
    printDebug(KEY_PRE_AUTHN_FILTER, "Auth providers array  : " + authProvidersIds.toString());

    if (request.hasHeader(authHeaderName)) {
        authHeader = request.getHeader(authHeaderName);
    } else if (request.hasHeader(COOKIE_HEADER)) {
        //Authentiction with HTTP cookies
        isCookie = config:contains(COOKIE_HEADER);
        if (isCookie) {
            authCookie = getAuthCookieIfPresent(request);
            if (authCookie is string) {
                authHeader = authCookie;
            }
        }
    }
    string providerId;
    if (!isCookie) {
        providerId = getAuthenticationProviderType(authHeader);
    } else {
        providerId = getAuthenticationProviderTypeWithCookie(authHeader);
    }
    printDebug(KEY_PRE_AUTHN_FILTER, "Provider Id for authentication handler : " + providerId);
    boolean canHandleAuthentication = false;
    foreach string provider in authProvidersIds {
        if (provider == providerId) {
            canHandleAuthentication = true;
        }
    }

    if(isSecuredResource && !request.hasHeader(authHeaderName)) {
        printDebug(KEY_PRE_AUTHN_FILTER, "Authentication header is missing for secured resource");
        setErrorMessageToInvocationContext(API_AUTH_MISSING_CREDENTIALS);
        setErrorMessageToFilterContext(context,API_AUTH_MISSING_CREDENTIALS);
        sendErrorResponse(caller, request, context);
        return false;
    }

    if (!canHandleAuthentication) {
        setErrorMessageToInvocationContext(API_AUTH_PROVIDER_INVALID);
        setErrorMessageToFilterContext(context,API_AUTH_PROVIDER_INVALID);
        sendErrorResponse(caller, request, context);
        return false;
    }
    // if auth providers are there, use those to authenticate

        //TODO: Move this to post authentication handler
        //checkAndRemoveAuthHeaders(request, authHeaderName);
    return true;
}

function getAuthenticationProviderType(string authHeader) returns (string) {
    if (contains(authHeader, AUTH_SCHEME_BASIC)){
        return AUTHN_SCHEME_BASIC;
    } else if (contains(authHeader,AUTH_SCHEME_BEARER) && contains(authHeader,".")) {
        return AUTH_SCHEME_JWT;
    } else {
        return AUTH_SCHEME_OAUTH2;
    }
}


function getAuthenticationProviderTypeWithCookie(string authHeader) returns (string) {
    if (contains(authHeader,".")) {
        return AUTH_SCHEME_JWT;
    } else {
        return AUTH_SCHEME_OAUTH2;
    }
}

function checkAndRemoveAuthHeaders(http:Request request, string authHeaderName) {
    if (getConfigBooleanValue(AUTH_CONF_INSTANCE_ID, REMOVE_AUTH_HEADER_FROM_OUT_MESSAGE, true)) {
        request.removeHeader(authHeaderName);
        printDebug(KEY_PRE_AUTHN_FILTER, "Removed header : " + authHeaderName + " from the request");
    }
    if (request.hasHeader(TEMP_AUTH_HEADER)) {
        request.setHeader(AUTH_HEADER, request.getHeader(TEMP_AUTH_HEADER));
        printDebug(KEY_PRE_AUTHN_FILTER, "Setting the backed up auth header value to the header: " + AUTH_HEADER);
        request.removeHeader(TEMP_AUTH_HEADER);
        printDebug(KEY_PRE_AUTHN_FILTER, "Removed header : " + TEMP_AUTH_HEADER + " from the request");
    }
}

function getAuthCookieIfPresent(http:Request request) returns string? {
    //get required cookie as config value
    string? authCookie = ();
    if (request.hasHeader(COOKIE_HEADER)) {
        string requiredCookie = config:getAsString(COOKIE_HEADER, "");
        //extract cookies from the incoming request
        string authHead = request.getHeader(COOKIE_HEADER);
        string[] cookies = split(authHead.trim(), ";");
        foreach var cookie in cookies {
            string converted = replaceFirst(cookie, "=", "::");
            string[] splitedStrings = split(converted.trim(), "::");
            string sessionId = splitedStrings[1];
            if (sessionId == requiredCookie) {
                authCookie = sessionId;
            }
        }
    }
    return authCookie;
}
