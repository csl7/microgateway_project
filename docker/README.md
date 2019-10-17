# Micro-GW Docker Base Image

## Building the image

1. Build the distribution(product-microgateway/distribution) package using 'mvn clean install'.
1. Then copy the 'wso2am-micro-gw-${MGW_VERSION}.zip' to the docker(product-microgateway/docker) directory.
1. Run the following command to build the base docker image. Command should be executed inside the docker directory

```docker build --no-cache=true --squash --build-arg MGW_DIST=wso2am-micro-gw-${MGW_VERSION}.zip -t wso2/wso2micro-gw:3.1.0 .```

NOTE : Please replace the '${MGW_VERSION}' with the relevant microgateway version. For ex: 3.1.0