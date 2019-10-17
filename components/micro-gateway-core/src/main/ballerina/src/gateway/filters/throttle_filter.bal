// Copyright (c) 2019 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
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
import ballerina/runtime;

public type ThrottleFilter object {
    public map<boolean> deployedPolicies = {};

    public function __init(map<boolean> deployedPolicies) {
        self.deployedPolicies = deployedPolicies;
    }

    public function filterRequest(http:Caller caller, http:Request request, http:FilterContext context) returns boolean {
        int startingTime = getCurrentTime();
        checkOrSetMessageID(context);
        boolean result = doThrottleFilterRequest(caller, request, context, self.deployedPolicies);
        setLatency(startingTime, context, THROTTLE_LATENCY);
        return result;
    }

    public function filterResponse(http:Response response, http:FilterContext context) returns boolean {
        return true;
    }
};

// TODO: need to refactor this function.
function doThrottleFilterRequest(http:Caller caller, http:Request request, http:FilterContext context,map<boolean>
    deployedPolicies) returns boolean {
    runtime:InvocationContext invocationContext = runtime:getInvocationContext();
    printDebug(KEY_THROTTLE_FILTER, "Processing the request in ThrottleFilter");
    //Throttle Tiers
    string applicationLevelTier;
    string subscriptionLevelTier;
    //Throttled decisions
    boolean isThrottled = false;
    boolean stopOnQuota;
    string apiContext = getContext(context);
    boolean isSecured = <boolean>invocationContext.attributes[IS_SECURED];
    context.attributes[ALLOWED_ON_QUOTA_REACHED] = false;
    context.attributes[IS_THROTTLE_OUT] = false;

    AuthenticationContext keyValidationResult = {};
    if (invocationContext.attributes.hasKey(AUTHENTICATION_CONTEXT)) {
        printDebug(KEY_THROTTLE_FILTER, "Context contains Authentication Context");
        keyValidationResult = <AuthenticationContext>invocationContext.attributes[AUTHENTICATION_CONTEXT];
        if (isRequestBlocked(caller, request, context, keyValidationResult)) {
            setThrottleErrorMessageToContext(context, FORBIDDEN, BLOCKING_ERROR_CODE,
                BLOCKING_MESSAGE, BLOCKING_DESCRIPTION);
            sendErrorResponse(caller, request, context);
            return false;
        }
        printDebug(KEY_THROTTLE_FILTER, "Checking subscription level throttle policy '" + keyValidationResult.
                tier + "' exist.");
        string? resourceLevelPolicyName = getResourceLevelPolicy(context);
        if(resourceLevelPolicyName is string) {
            printDebug(KEY_THROTTLE_FILTER, "Resource level throttle policy : " + resourceLevelPolicyName);
            if(resourceLevelPolicyName.length() > 0 && resourceLevelPolicyName != UNLIMITED_TIER && !isPolicyExist(deployedPolicies, resourceLevelPolicyName)) {
                printDebug(KEY_THROTTLE_FILTER, "Resource level throttle policy '" + resourceLevelPolicyName
                        + "' does not exist.");
                setThrottleErrorMessageToContext(context, INTERNAL_SERVER_ERROR,
                    INTERNAL_ERROR_CODE_POLICY_NOT_FOUND,
                    INTERNAL_SERVER_ERROR_MESSAGE, POLICY_NOT_FOUND_DESCRIPTION);
                sendErrorResponse(caller, request, context);
                return false;
            }
        }
        printDebug(KEY_THROTTLE_FILTER, "Checking resource level throttling-out.");
        if (isResourceLevelThrottled(context, keyValidationResult, resourceLevelPolicyName)) {
            printDebug(KEY_THROTTLE_FILTER, "Resource level throttled out. Sending throttled out response.");
            context.attributes[IS_THROTTLE_OUT] = true;
            context.attributes[THROTTLE_OUT_REASON] = THROTTLE_OUT_REASON_RESOURCE_LIMIT_EXCEEDED;
            setThrottleErrorMessageToContext(context, THROTTLED_OUT, RESOURCE_THROTTLE_OUT_ERROR_CODE,
                THROTTLE_OUT_MESSAGE, THROTTLE_OUT_DESCRIPTION);
            sendErrorResponse(caller, request, context);
            return false;
        } else {
            printDebug(KEY_THROTTLE_FILTER, "Resource level throttled out: false");
        }

        if (keyValidationResult.tier != UNLIMITED_TIER && !isPolicyExist(deployedPolicies, keyValidationResult.tier)) {
            printDebug(KEY_THROTTLE_FILTER, "Subscription level throttle policy '" + keyValidationResult.tier
                    + "' does not exist.");
            setThrottleErrorMessageToContext(context, INTERNAL_SERVER_ERROR,
                INTERNAL_ERROR_CODE_POLICY_NOT_FOUND,
                INTERNAL_SERVER_ERROR_MESSAGE, POLICY_NOT_FOUND_DESCRIPTION);
            sendErrorResponse(caller, request, context);
            return false;
        }
        printDebug(KEY_THROTTLE_FILTER, "Checking subscription level throttling-out.");
        [isThrottled, stopOnQuota] = isSubscriptionLevelThrottled(context, keyValidationResult);
        printDebug(KEY_THROTTLE_FILTER, "Subscription level throttling result:: isThrottled:"
                + isThrottled.toString() + ", stopOnQuota:" + stopOnQuota.toString());
        if (isThrottled) {
            if (stopOnQuota) {
                printDebug(KEY_THROTTLE_FILTER, "Sending throttled out responses.");
                context.attributes[IS_THROTTLE_OUT] = true;
                context.attributes[THROTTLE_OUT_REASON] = THROTTLE_OUT_REASON_SUBSCRIPTION_LIMIT_EXCEEDED;
                setThrottleErrorMessageToContext(context, THROTTLED_OUT, SUBSCRIPTION_THROTTLE_OUT_ERROR_CODE,
                    THROTTLE_OUT_MESSAGE, THROTTLE_OUT_DESCRIPTION);
                sendErrorResponse(caller, request, context);
                return false;
            } else {
                // set properties in order to publish into analytics for billing
                context.attributes[ALLOWED_ON_QUOTA_REACHED] = true;
                printDebug(KEY_THROTTLE_FILTER, "Proceeding(1st) since stopOnQuota is set to false.");
            }
        }
        printDebug(KEY_THROTTLE_FILTER, "Checking application level throttle policy '"
                + keyValidationResult.applicationTier + "' exist.");
        if (keyValidationResult.applicationTier != UNLIMITED_TIER &&
            !isPolicyExist(deployedPolicies, keyValidationResult.applicationTier)) {
            printDebug(KEY_THROTTLE_FILTER, "Application level throttle policy '"
                    + keyValidationResult.applicationTier + "' does not exist.");
            setThrottleErrorMessageToContext(context, INTERNAL_SERVER_ERROR,
                INTERNAL_ERROR_CODE_POLICY_NOT_FOUND,
                INTERNAL_SERVER_ERROR_MESSAGE, POLICY_NOT_FOUND_DESCRIPTION);
            sendErrorResponse(caller, request, context);
            return false;
        }
        printDebug(KEY_THROTTLE_FILTER, "Checking application level throttling-out.");
        if (isApplicationLevelThrottled(keyValidationResult)) {
            printDebug(KEY_THROTTLE_FILTER, "Application level throttled out. Sending throttled out response.");
            context.attributes[IS_THROTTLE_OUT] = true;
            context.attributes[THROTTLE_OUT_REASON] = THROTTLE_OUT_REASON_APPLICATION_LIMIT_EXCEEDED;
            setThrottleErrorMessageToContext(context, THROTTLED_OUT, APPLICATION_THROTTLE_OUT_ERROR_CODE,
                THROTTLE_OUT_MESSAGE, THROTTLE_OUT_DESCRIPTION);
            sendErrorResponse(caller, request, context);
            return false;
        } else {
            printDebug(KEY_THROTTLE_FILTER, "Application level throttled out: false");
        }

    } else if (!isSecured) {
        printDebug(KEY_THROTTLE_FILTER, "Not a secured resource. Proceeding with Unauthenticated tier.");
        // setting keytype to invocationContext
        invocationContext.attributes[KEY_TYPE_ATTR] = PRODUCTION_KEY_TYPE;

        printDebug(KEY_THROTTLE_FILTER, "Checking unauthenticated throttle policy '" + UNAUTHENTICATED_TIER
                + "' exist.");
        if (!isPolicyExist(deployedPolicies, UNAUTHENTICATED_TIER)) {
            printDebug(KEY_THROTTLE_FILTER, "Unauthenticated throttle policy '" + UNAUTHENTICATED_TIER
                    + "' is not exist.");
            setThrottleErrorMessageToContext(context, INTERNAL_SERVER_ERROR,
                INTERNAL_ERROR_CODE_POLICY_NOT_FOUND,
                INTERNAL_SERVER_ERROR_MESSAGE, POLICY_NOT_FOUND_DESCRIPTION);
            sendErrorResponse(caller, request, context);
            return false;
        }
        [isThrottled, stopOnQuota] = isUnauthenticateLevelThrottled(context);
        printDebug(KEY_THROTTLE_FILTER, "Unauthenticated tier throttled out result:: isThrottled:"
                + isThrottled.toString() + ", stopOnQuota:" + stopOnQuota.toString());
        if (isThrottled) {
            if (stopOnQuota) {
                printDebug(KEY_THROTTLE_FILTER, "Sending throttled out response.");
                context.attributes[IS_THROTTLE_OUT] = true;
                context.attributes[THROTTLE_OUT_REASON] = THROTTLE_OUT_REASON_SUBSCRIPTION_LIMIT_EXCEEDED;
                setThrottleErrorMessageToContext(context, THROTTLED_OUT, SUBSCRIPTION_THROTTLE_OUT_ERROR_CODE,
                    THROTTLE_OUT_MESSAGE, THROTTLE_OUT_DESCRIPTION);
                sendErrorResponse(caller, request, context);
                return false;
            } else {
                // set properties in order to publish into analytics for billing
                context.attributes[ALLOWED_ON_QUOTA_REACHED] = true;
                printDebug(KEY_THROTTLE_FILTER, "Proceeding(2nd) since stopOnQuota is set to false.");
            }
        }
        string clientIp = <string>context.attributes[REMOTE_ADDRESS];
        keyValidationResult.authenticated = true;
        keyValidationResult.tier = UNAUTHENTICATED_TIER;
        keyValidationResult.stopOnQuotaReach = true;
        keyValidationResult.apiKey = clientIp;
        keyValidationResult.username = END_USER_ANONYMOUS;
        keyValidationResult.applicationId = clientIp;
        keyValidationResult.keyType = PRODUCTION_KEY_TYPE;
        // setting keytype to invocationContext
        invocationContext.attributes[KEY_TYPE_ATTR] = keyValidationResult.keyType;
    } else {
        printDebug(KEY_THROTTLE_FILTER, "Unknown error.");
        setThrottleErrorMessageToContext(context, INTERNAL_SERVER_ERROR, INTERNAL_ERROR_CODE,
            INTERNAL_SERVER_ERROR_MESSAGE, INTERNAL_SERVER_ERROR_MESSAGE);
        sendErrorResponse(caller, request, context);
        return false;
    }

    //Publish throttle event to another worker flow to publish to internal policies or traffic manager
    RequestStreamDTO throttleEvent = generateThrottleEvent(request, context, keyValidationResult);
    future<()> publishedEvent = start asyncPublishEvent(throttleEvent);
    printDebug(KEY_THROTTLE_FILTER, "Request is not throttled");
    return true;
}

function asyncPublishEvent(RequestStreamDTO throttleEvent) {
    printDebug(KEY_THROTTLE_FILTER, "Checking application sending throttle event to another worker.");
    publishNonThrottleEvent(throttleEvent);
}

function setThrottleErrorMessageToContext(http:FilterContext context, int statusCode, int errorCode, string
    errorMessage, string errorDescription) {
    context.attributes[HTTP_STATUS_CODE] = statusCode;
    context.attributes[FILTER_FAILED] = true;
    context.attributes[ERROR_CODE] = errorCode;
    context.attributes[ERROR_MESSAGE] = errorMessage;
    context.attributes[ERROR_DESCRIPTION] = errorDescription;
}

function isSubscriptionLevelThrottled(http:FilterContext context, AuthenticationContext keyValidationDto) returns [
    boolean, boolean] {
    if (keyValidationDto.tier == UNLIMITED_TIER) {
        return [false, false];
    }

    string? apiVersion = getVersion(context);
    string subscriptionLevelThrottleKey = keyValidationDto.applicationId + ":" + getContext(context);
    if (apiVersion is string) {
        subscriptionLevelThrottleKey += ":" + apiVersion;
    }
    printDebug(KEY_THROTTLE_FILTER, "Subscription level throttle key : " + subscriptionLevelThrottleKey);
    return isRequestThrottled(subscriptionLevelThrottleKey);
}

function isApplicationLevelThrottled(AuthenticationContext keyValidationDto) returns (boolean) {
    if (keyValidationDto.applicationTier == UNLIMITED_TIER) {
        return false;
    }
    string applicationLevelThrottleKey = keyValidationDto.applicationId + ":" + keyValidationDto.username;
    printDebug(KEY_THROTTLE_FILTER, "Application level throttle key : " + applicationLevelThrottleKey);
    boolean throttled;
    boolean stopOnQuota;
    [throttled, stopOnQuota] = isRequestThrottled(applicationLevelThrottleKey);
    return throttled;
}


function isResourceLevelThrottled(http:FilterContext context,AuthenticationContext keyValidationDto, string? policy) returns (boolean) {
    if (policy is string) {
        if (policy == UNLIMITED_TIER) {
            return false;
        }
        
        // TODO: Need to discuss if we should valdate the () case of apiVersion property
        string? apiVersion = getVersion(context);
        string resourceLevelThrottleKey = replaceAll(context.getResourceName(), "_", "");
        if (apiVersion is string) {
            resourceLevelThrottleKey += ":" + apiVersion;
        }
        printDebug(KEY_THROTTLE_FILTER, "Resource level throttle key : " + resourceLevelThrottleKey);
        boolean throttled;
        boolean stopOnQuota;
        [throttled, stopOnQuota] = isRequestThrottled(resourceLevelThrottleKey);
        return throttled;
    }
    return false;
}

function getResourceLevelPolicy(http:FilterContext context) returns string? {
    TierConfiguration? tier = resourceTierAnnotationMap[context.getResourceName()];
    return (tier is TierConfiguration) ? tier.policy : ();
}

function isUnauthenticateLevelThrottled(http:FilterContext context) returns [boolean, boolean] {
    string clientIp = <string>context.attributes[REMOTE_ADDRESS];
    string? apiVersion = getVersion(context);
    string throttleKey = clientIp + ":" + getContext(context);
    if (apiVersion is string) {
        throttleKey += ":" + apiVersion;
    }
    return isRequestThrottled(throttleKey);
}
function isRequestBlocked(http:Caller caller, http:Request request, http:FilterContext context, AuthenticationContext keyValidationResult) returns (boolean) {
    string apiLevelBlockingKey = getContext(context);
    string apiTenantDomain = getTenantDomain(context);
    string ipLevelBlockingKey = apiTenantDomain + ":" + getClientIp(request, caller);
    string appLevelBlockingKey = keyValidationResult.subscriber + ":" + keyValidationResult.applicationName;
    if (isAnyBlockConditionExist() && (isBlockConditionExist(apiLevelBlockingKey) ||
    isBlockConditionExist(ipLevelBlockingKey) || isBlockConditionExist(appLevelBlockingKey)) ||
    isBlockConditionExist(keyValidationResult.username)) {
        return true;
    } else {
        return false;
    }
}

function generateThrottleEvent(http:Request req, http:FilterContext context, AuthenticationContext keyValidationDto)
    returns (RequestStreamDTO) {
    RequestStreamDTO requestStreamDto = {};
    string? apiVersion = getVersion(context);
    requestStreamDto.messageID = <string>context.attributes[MESSAGE_ID];
    requestStreamDto.apiKey = getContext(context);
    requestStreamDto.appKey = keyValidationDto.applicationId + ":" + keyValidationDto.username;
    requestStreamDto.subscriptionKey = keyValidationDto.applicationId + ":" + getContext(context);
    requestStreamDto.appTier = keyValidationDto.applicationTier;
    requestStreamDto.apiTier = keyValidationDto.apiTier;
    requestStreamDto.subscriptionTier = keyValidationDto.tier;
    string resourcekey = context.getResourceName();
    requestStreamDto.resourceKey = replaceAll(resourcekey, "_", "");
    TierConfiguration? tier = resourceTierAnnotationMap[resourcekey];
    string? policy = (tier is TierConfiguration) ? tier.policy : ();
    if (policy is string) {
       requestStreamDto.resourceTier = policy;
    }

    requestStreamDto.userId = keyValidationDto.username;
    requestStreamDto.apiContext = getContext(context);
    if (apiVersion is string) {
        requestStreamDto.apiVersion = apiVersion;
    }
    requestStreamDto.appTenant = keyValidationDto.subscriberTenantDomain;
    requestStreamDto.apiTenant = getTenantDomain(context);
    requestStreamDto.apiName = getApiName(context);
    requestStreamDto.appId = keyValidationDto.applicationId;

    if (apiVersion is string) {
        requestStreamDto.apiKey += ":" + apiVersion;
        requestStreamDto.subscriptionKey +=":" + apiVersion;
        requestStreamDto.resourceKey += ":" + apiVersion;
    }
    printDebug(KEY_THROTTLE_FILTER, "Resource key : " + requestStreamDto.resourceKey);
    printDebug(KEY_THROTTLE_FILTER, "Subscription key : " + requestStreamDto.subscriptionKey);
    printDebug(KEY_THROTTLE_FILTER, "App key : " + requestStreamDto.appKey);
    printDebug(KEY_THROTTLE_FILTER, "API key : " + requestStreamDto.apiKey);
    printDebug(KEY_THROTTLE_FILTER, "Resource Tier : " + requestStreamDto.resourceTier);
    printDebug(KEY_THROTTLE_FILTER, "Subscription Tier : " + requestStreamDto.subscriptionTier);
    printDebug(KEY_THROTTLE_FILTER, "App Tier : " + requestStreamDto.appTier);
    printDebug(KEY_THROTTLE_FILTER, "API Tier : " + requestStreamDto.apiTier);

    json properties = {};
    requestStreamDto.properties = properties.toString();
    return requestStreamDto;
}

function getVersion(http:FilterContext context) returns string|() {
    string? apiVersion = "";
    APIConfiguration? apiConfiguration = apiConfigAnnotationMap[context.getServiceName()];
    if (apiConfiguration is APIConfiguration) {
        apiVersion = apiConfiguration.apiVersion;
    }

    return apiVersion;
}
