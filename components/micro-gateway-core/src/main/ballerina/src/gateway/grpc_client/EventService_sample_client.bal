// public function main (string... args) {

//     EventServiceBlockingClient blockingEp = new("http://localhost:9090");

// }

import ballerina/grpc;
import ballerina/io;

// EventServiceClient analyticsClient = new("http://localhost:9806");


EventServiceClient analyticsClient = new("https://localhost:9806", {
    secureSocket:{
            trustStore: {
                  path: getConfigValue(LISTENER_CONF_INSTANCE_ID, TRUST_STORE_PATH,
                      "/home/lahiru/Documents/Myproject/jballerinaForThrottling/product-microgateway/components/micro-gateway-core/target/extracted-distribution/jballerina-tools-1.0.0/bre/security/client-truststore.jks"),
                  password: getConfigValue(LISTENER_CONF_INSTANCE_ID, TRUST_STORE_PASSWORD, "wso2carbon")
            }
        }
});



service EventServiceMessageListner = service {
        resource function onMessage(string message) {
        // total = 1;
        io:println("Response received from server: " + message);
    }

    resource function onError(error err) {
        io:println("Error reported from server: " + err.reason() + " - "
                                           + <string> err.detail()["message"]);
}

    resource function onComplete() {
        // total = 1;
        io:println("Server Complete Sending Responses.");
    }
};

public function dataToAnalytics(string payloadString, string streamId){
    io:println("Grpc :" + streamId +"triggered------------------------>>>>>>>>>>>>>>>>>" );
    grpc:StreamingClient ep;
    var res = analyticsClient->consume(EventServiceMessageListner);
    // var res = analyticsClient->consume();
    if(res is grpc:Error){
        io:println("Error from connector :" + res.reason()+ " - " + <string>res.detail()["message"]);
        return ;
    }
    else{
        io:println("Initialized Connection Successfully");
        ep = res;
    }
    Event event = {payload:payloadString,
    headers: [{key:"stream.id", value:streamId}]};
    grpc:Error? connErr = ep->send(event);
        if (connErr is grpc:Error) {
            io:println("Error from Connector: " + connErr.reason() + " - "
                                       + <string> connErr.detail()["message"]);
        } else {
            io:println("send greeting successfully");
        }
}

public function throttlingDataToAnalytics(){

}


public function faultDataToAnalytics(){
    
}
