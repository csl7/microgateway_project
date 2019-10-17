/*
 * Copyright (c) WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
 *
 * WSO2 Inc. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package org.wso2.micro.gateway.tests.listener;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testng.IExecutionListener;
import org.wso2.micro.gateway.tests.context.Constants;
import org.wso2.micro.gateway.tests.context.MicroGWTestException;
import org.wso2.micro.gateway.tests.context.Server;
import org.wso2.micro.gateway.tests.context.ServerInstance;

import java.io.File;
import java.util.List;

/**
 * TestNg listener to start and stop a server before all test classes are executed for integration test.
 * This class should be registered in testng.xml under listener section.
 */
public class TestExecutionListener implements IExecutionListener {
    private static final Logger log = LoggerFactory.getLogger(TestExecutionListener.class);

    private static ServerInstance newServer;

    /**
     * This method will execute before all the test classes are executed and this will start a server
     * with sample rest files deployed.
     *
     */
    @Override
    public void onExecutionStart() {

        try {
            String relativePath = new File("src" + File.separator + "test" + File.separator + "resources"
                    + File.separator + "apis" + File.separator + "common_backend.bal").getAbsolutePath();
            newServer = ServerInstance.initMicroGwServer();
            String configPath = new File("src" + File.separator + "test" + File.separator + "resources"
                    + File.separator + "confs" + File.separator + "startup.conf").getAbsolutePath();
            newServer.startMicroGwServerWithConfigPath(relativePath, configPath);

        } catch (MicroGWTestException e) {
            log.error("Server failed to start. " + e.getMessage(), e);
            throw new RuntimeException("Server failed to start. " + e.getMessage(), e);
        }
    }

    /**
     * This method will execute after all the test classes are executed and this will stop the server
     * started by start method.
     *
     */
    @Override
    public void onExecutionFinish() {
        if (newServer != null && newServer.isRunning()) {
            try {
                newServer.stopServer(true);
            } catch (Exception e) {
                log.error("Server failed to stop. " + e.getMessage(), e);
                throw new RuntimeException("Server failed to stop. " + e.getMessage(), e);
            }
        }
    }

    /**
     * To het the server instance started by listener.
     * @return up and running server instance.
     */
    public static Server getServerInstance() {
        if (newServer == null || !newServer.isRunning()) {
            throw new RuntimeException("Server startup failed");
        }
        return newServer;
    }

    /**
     * List the file in a given directory.
     *
     * @param path of the directory
     * @param list   collection of files found
     * @return String arrays of file absolute paths
     */
    private static String[] listFiles(String path, List<String> list) {
        File folder = new File(path);
        File[] listOfFiles = folder.listFiles();
        if (list.size() > 100) {
            //returning the search when it comes to 100 files
            log.warn("Sample file deployment restricted to 100 files");
            return list.toArray(new String[]{});
        }
        if (listOfFiles != null) {
            for (File file : listOfFiles) {
                if (file.isDirectory()) {
                    log.info("Searching rest ballerina files in " + file.getPath());
                    listFiles(file.getAbsolutePath(), list);
                } else {
                    if (file.getPath().endsWith(Constants.SERVICE_FILE_EXTENSION)) {
                        log.info("Adding file " + file.getPath());
                        list.add(file.getAbsolutePath());
                    }
                }
            }
        }
        return list.toArray(new String[]{});
    }
}

