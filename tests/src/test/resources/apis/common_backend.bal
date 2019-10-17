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
import ballerina/io;
import wso2/gateway;

endpoint gateway:APIGatewayListener echoEP {
    port:9099
};

@http:ServiceConfig {
    basePath:"/echo"
}
service<http:Service> echo bind echoEP{

    @http:ResourceConfig {
        methods:["POST"],
        path:"/"
    }
    echo (endpoint caller, http:Request req) {
        http:Response resp = new;
        var result = req.getTextPayload();
        match result {
            error payloadError => io:println(payloadError.message);
            string payload => {
                resp.setTextPayload(payload);
                _ = caller -> respond(resp);
            }
        }
    }
}
