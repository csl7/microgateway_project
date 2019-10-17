// Copyright (c)  WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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
import ballerina /io;

public type AnalyticsRequestFilter object {

    public function filterRequest(http:Caller caller, http:Request request, http:FilterContext context) returns boolean {
        //Filter only if analytics is enabled.
        if (isAnalyticsEnabled) {
            checkOrSetMessageID(context);
            context.attributes[PROTOCOL_PROPERTY] = caller.protocol;
            doFilterRequest(request, context);
        }
        return true;
    }

    public function filterResponse(http:Response response, http:FilterContext context) returns boolean {

        if (isAnalyticsEnabled) {
            boolean filterFailed = <boolean>context.attributes[FILTER_FAILED];
            if (context.attributes.hasKey(IS_THROTTLE_OUT)) {
                boolean isThrottleOut = <boolean>context.attributes[IS_THROTTLE_OUT];
                if (isThrottleOut) {
                    io:println("ThrottleAnalyticsEventDTO is going to print -->");
                    ThrottleAnalyticsEventDTO|error throttleAnalyticsEventDTO = trap populateThrottleAnalyticsDTO(context);
                    io:println(throttleAnalyticsEventDTO.toString());
                    if(throttleAnalyticsEventDTO is ThrottleAnalyticsEventDTO) {
                        EventDTO|error eventDTO  = trap getEventFromThrottleData(throttleAnalyticsEventDTO);
                        if(eventDTO is EventDTO) {
                            io:println("This is the event DTO of throttling -->");
                            //eventStream.publish(eventDTO);
                            // ####################################################
                            json analyticsThrottleJSON = createThrottleJSON(throttleAnalyticsEventDTO);
                            dataToAnalytics(analyticsThrottleJSON.toJsonString() , "InComingThrottledOutStream");
                            // ####################################################
                            io:println(eventDTO.toString());
                        } else {
                            printError(KEY_ANALYTICS_FILTER, "Error while creating throttle analytics event");
                            printFullError(KEY_ANALYTICS_FILTER, eventDTO);
                        }
                    } else {
                        printError(KEY_ANALYTICS_FILTER, "Error while populating throttle analytics event data");
                        printFullError(KEY_ANALYTICS_FILTER, throttleAnalyticsEventDTO);
                    }
                } else {
                    if (!filterFailed) {
                        doFilterAll(response, context);
                    }
                }
            } else {
                if (!filterFailed) {
                    context.attributes[THROTTLE_LATENCY] = 0;
                    doFilterAll(response, context);
                }
            }
        }
        return true;
    }

};


function doFilterRequest(http:Request request, http:FilterContext context) {
    error? result = trap setRequestAttributesToContext(request, context);
    if(result is error) {
        printError(KEY_ANALYTICS_FILTER, "Error while setting analytics data in request path");
        printFullError(KEY_ANALYTICS_FILTER, result);
    }
}

function doFilterFault(http:FilterContext context, string errorMessage) {
    FaultDTO|error faultDTO = trap populateFaultAnalyticsDTO(context, errorMessage);
    io:println("This is first falut DTO :" + faultDTO.toString());
    if(faultDTO is FaultDTO) {
        EventDTO|error eventDTO = trap getEventFromFaultData(faultDTO);
        if(eventDTO is EventDTO) {
            io:println("This is the falut event DTO");

            //eventStream.publish(eventDTO);
            //eventStream.publish(eventDTO);
            // ####################################################
            json analyticsFaultJSON = createFaultJSON(faultDTO);
            dataToAnalytics(analyticsFaultJSON.toJsonString() , "FaultStream");
            // ####################################################
            io:println(eventDTO.toString());
        } else {
            printError(KEY_ANALYTICS_FILTER, "Error while genaratting analytics data for fault event");
            printFullError(KEY_ANALYTICS_FILTER, eventDTO);
        }
    } else {
        printError(KEY_ANALYTICS_FILTER, "Error while populating analytics fault event data");
        printFullError(KEY_ANALYTICS_FILTER, faultDTO);
    }
}

function doFilterResponseData(http:Response response, http:FilterContext context) {
    //Response data publishing
    RequestResponseExecutionDTO|error requestResponseExecutionDTO = trap generateRequestResponseExecutionDataEvent(response,
        context);
    if(requestResponseExecutionDTO is RequestResponseExecutionDTO) {
        EventDTO|error event = trap generateEventFromRequestResponseExecutionDTO(requestResponseExecutionDTO);
        if(event is EventDTO) {
            // eventStream.publish(event);
            // ###############################################
            json analyticsResponseJSON = createAnalyticsJSON(requestResponseExecutionDTO);
            dataToAnalytics(analyticsResponseJSON.toJsonString() , "InComingRequestStream");
            io:println("\n\n\nTo json string : " + analyticsResponseJSON.toJsonString() );
            io:println("\n\n\nTo  string : " + analyticsResponseJSON.toString() );
            // ##############################################
        } else {
            printError(KEY_ANALYTICS_FILTER, "Error while genarating analytics data event");
            printFullError(KEY_ANALYTICS_FILTER, event);
        }
    } else {
        printError(KEY_ANALYTICS_FILTER, "Error while publishing analytics data");
        printFullError(KEY_ANALYTICS_FILTER, requestResponseExecutionDTO);
    }
}

function doFilterAll(http:Response response, http:FilterContext context) {
    var resp = runtime:getInvocationContext().attributes[ERROR_RESPONSE];
    if (resp is ()) {
        printDebug(KEY_ANALYTICS_FILTER, "No any faulty analytics events to handle.");
        doFilterResponseData(response, context);
    } else if(resp is string) {
        printDebug(KEY_ANALYTICS_FILTER, "Error response value present and handling faulty analytics events");
        doFilterFault(context, resp);
    }
}



//#####################################################################




public function createAnalyticsJSON(RequestResponseExecutionDTO requestResponseExecutionDTO) returns json {

    json analyticsJSON = {
        meta_clientType : <string>requestResponseExecutionDTO.metaClientType ,
        applicationConsumerKey : <string>requestResponseExecutionDTO.applicationConsumerKey ,
        applicationName : <string>requestResponseExecutionDTO.applicationName ,
        applicationId : <string>requestResponseExecutionDTO.applicationId ,
        applicationOwner : <string>requestResponseExecutionDTO.applicationOwner ,

        apiContext : <string>requestResponseExecutionDTO.apiContext ,
        apiName : <string> requestResponseExecutionDTO.apiName ,
        apiVersion : <string>requestResponseExecutionDTO.apiVersion ,
        apiResourcePath : <string>requestResponseExecutionDTO.apiResourcePath ,
        apiResourceTemplate : <string>requestResponseExecutionDTO.apiResourceTemplate ,

        apiMethod : <string>requestResponseExecutionDTO.apiMethod ,
        apiCreator : <string>requestResponseExecutionDTO.apiCreator ,
        apiCreatorTenantDomain : <string>requestResponseExecutionDTO.apiCreatorTenantDomain ,
        apiTier :  <string>requestResponseExecutionDTO.apiTier ,
        apiHostname : <string>requestResponseExecutionDTO.apiHostname ,

        username : <string>requestResponseExecutionDTO.userName ,
        userTenantDomain :  <string>requestResponseExecutionDTO.userTenantDomain ,
        userIp :  <string>requestResponseExecutionDTO.userIp ,
        userAgent : <string>requestResponseExecutionDTO.userAgent ,
        requestTimestamp : requestResponseExecutionDTO.requestTimestamp ,

        throttledOut : requestResponseExecutionDTO.throttledOut ,
        responseTime : requestResponseExecutionDTO.responseTime ,
        serviceTime : requestResponseExecutionDTO.serviceTime ,
        backendTime : requestResponseExecutionDTO.backendTime ,
        responseCacheHit : requestResponseExecutionDTO.responseCacheHit ,

        responseSize : requestResponseExecutionDTO.responseSize ,
        protocol : requestResponseExecutionDTO.protocol ,
        responseCode : requestResponseExecutionDTO.responseCode ,
        destination : requestResponseExecutionDTO.destination ,
        securityLatency : requestResponseExecutionDTO.executionTime.securityLatency ,

        throttlingLatency : requestResponseExecutionDTO.executionTime.throttlingLatency , 
        requestMedLat : requestResponseExecutionDTO.executionTime.requestMediationLatency ,
        responseMedLat :requestResponseExecutionDTO.executionTime.responseMediationLatency , 
        backendLatency : requestResponseExecutionDTO.executionTime.backEndLatency , 
        otherLatency : requestResponseExecutionDTO.executionTime.otherLatency , 

        gatewayType : <string>requestResponseExecutionDTO.gatewayType , 
        label : <string>requestResponseExecutionDTO.label
    };  

    return analyticsJSON;
}


public function createThrottleJSON(ThrottleAnalyticsEventDTO throttleAnalyticsEventDTO) returns json{
        json throttleJSON = {
            meta_clientType : throttleAnalyticsEventDTO.metaClientType,
            username : throttleAnalyticsEventDTO.userName,
            userTenantDomain : throttleAnalyticsEventDTO.userTenantDomain,
            apiName :throttleAnalyticsEventDTO.apiName,
            apiVersion : throttleAnalyticsEventDTO.apiVersion,
            apiContext : throttleAnalyticsEventDTO.apiContext,
            apiCreator : throttleAnalyticsEventDTO.apiCreator,
            apiCreatorTenantDomain : throttleAnalyticsEventDTO.apiCreatorTenantDomain,
            applicationId : throttleAnalyticsEventDTO.applicationId,
            applicationName : throttleAnalyticsEventDTO.applicationName,
            subscriber : throttleAnalyticsEventDTO.subscriber,
            throttledOutReason : throttleAnalyticsEventDTO.throttledOutReason,
            gatewayType : throttleAnalyticsEventDTO.gatewayType,
            throttledOutTimestamp : throttleAnalyticsEventDTO.throttledTime,
            hostname : throttleAnalyticsEventDTO.hostname
        };

        return throttleJSON;
}



public function createFaultJSON(FaultDTO faultDTO)returns json{
    json falutJSON = {
        meta_clientType : faultDTO. metaClientType,
        applicationConsumerKey : faultDTO.consumerKey,
        apiName : faultDTO.apiName,
        apiVersion : faultDTO.apiVersion,
        apiContext : faultDTO.apiContext,
        apiResourcePath : faultDTO.resourcePath,
        apiMethod : faultDTO.method,
        apiCreator : faultDTO.apiCreator,
        username : faultDTO.userName,
        userTenantDomain : faultDTO.userTenantDomain,
        apiCreatorTenantDomain : faultDTO.apiCreatorTenantDomain,
        hostname : faultDTO.hostName,
        applicationId : faultDTO.applicationId,
        applicationName : faultDTO.applicationName,
        protocol : faultDTO.protocol,
        errorCode : faultDTO.errorCode,
        errorMessage : faultDTO.errorMessage,
        requestTimestamp : faultDTO.faultTime
    };
    return falutJSON;
}
