/*
 * Copyright (c) 2018, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
 *
 * WSO2 Inc. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package org.wso2.apimgt.gateway.cli.cmd;

import com.beust.jcommander.JCommander;
import com.beust.jcommander.Parameter;
import com.beust.jcommander.Parameters;
import org.ballerinalang.packerina.cmd.CommandUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.wso2.apimgt.gateway.cli.codegen.CodeGenerationContext;
import org.wso2.apimgt.gateway.cli.codegen.CodeGenerator;
import org.wso2.apimgt.gateway.cli.codegen.ThrottlePolicyGenerator;
import org.wso2.apimgt.gateway.cli.config.TOMLConfigParser;
import org.wso2.apimgt.gateway.cli.constants.CliConstants;
import org.wso2.apimgt.gateway.cli.exception.CLIInternalException;
import org.wso2.apimgt.gateway.cli.exception.CLIRuntimeException;
import org.wso2.apimgt.gateway.cli.exception.ConfigParserException;
import org.wso2.apimgt.gateway.cli.model.config.Config;
import org.wso2.apimgt.gateway.cli.model.config.ContainerConfig;
import org.wso2.apimgt.gateway.cli.utils.CmdUtils;
import org.wso2.apimgt.gateway.cli.utils.ToolkitLibExtractionUtils;

import java.io.File;
import java.io.FilenameFilter;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * This class represents the "build" command and it holds arguments and flags specified by the user.
 */
@Parameters(commandNames = "build", commandDescription = "build a project")
public class BuildCmd implements LauncherCmd {
    private static final Logger logger = LoggerFactory.getLogger(BuildCmd.class);
    private static PrintStream outStream = System.out;

    @SuppressWarnings("unused")
    @Parameter(description = "project", required = true)
    private String projectName;

    @SuppressWarnings("unused")
    @Parameter(names = {"-d", "--deployment-config"}, description = "deployment-config file for docker/k8s")
    private String deploymentConfigPath;

    @SuppressWarnings("unused")
    @Parameter(names = {"--help", "-h", "?"}, description = "print command help", help = true)
    private boolean helpFlag;

    @SuppressWarnings("unused")
    @Parameter(names = "--java.debug", hidden = true)
    private String javaDebugPort;

    public void execute() {
        if (helpFlag) {
            String commandUsageInfo = getCommandUsageInfo("build");
            outStream.println(commandUsageInfo);
            return;
        }

        String projectName = this.projectName.replaceAll("[/\\\\]", "");
        File projectLocation = new File(CmdUtils.getProjectDirectoryPath(projectName));

        if (!projectLocation.exists()) {
            throw new CLIRuntimeException("Project " + projectName + " does not exist.");
        }
        //extract the ballerina platform and runtime
        ToolkitLibExtractionUtils.extractPlatformAndRuntime();

        String importedAPIDefLocation = CmdUtils.getProjectGenAPIDefinitionPath(projectName);
        String addedAPIDefLocation = CmdUtils.getProjectAPIFilesDirectoryPath(projectName);
        boolean isImportedAPIsAvailable = checkDirContentAvailability(importedAPIDefLocation);
        boolean isAddedAPIsAvailable = checkDirContentAvailability(addedAPIDefLocation);

        if (!isImportedAPIsAvailable && !isAddedAPIsAvailable) {
            throw new CLIRuntimeException("Nothing to build. API definitions does not exist.");
        }

        try {
            String toolkitConfigPath = CmdUtils.getMainConfigLocation();
            init(projectName, toolkitConfigPath, deploymentConfigPath);

            // Create policies directory
            String genPoliciesPath = CmdUtils.getProjectTargetModulePath(projectName) + File.separator
                    + CliConstants.GEN_POLICIES_DIR;
            CmdUtils.createDirectory(genPoliciesPath, false);

            // Generate policy definitions
            ThrottlePolicyGenerator policyGenerator = new ThrottlePolicyGenerator();
            policyGenerator.generate(genPoliciesPath, projectName);

            // Copy static source files
            CmdUtils.copyAndReplaceFolder(CmdUtils.getProjectInterceptorsPath(projectName),
                    CmdUtils.getProjectTargetInterceptorsPath(projectName));
            CmdUtils.copyFolder(CmdUtils.getProjectDirectoryPath(projectName) + File.separator
                            + CliConstants.PROJECT_SERVICES_DIR,
                    CmdUtils.getProjectTargetModulePath(projectName) + File.separator
                            + CliConstants.PROJECT_SERVICES_DIR);
            new CodeGenerator().generate(projectName, true);
        } catch (IOException e) {
            throw new CLIInternalException(
                    "Error occurred while generating source code for the open API definitions.", e);
        }
    }

    private boolean checkDirContentAvailability(String fileLocation) {
        File file = new File(fileLocation);
        FilenameFilter filter = (f, name) -> (name.endsWith(".yaml") || name.endsWith(".json"));
        String[] fileNames = file.list(filter);

        return file.list() != null && fileNames != null && fileNames.length > 0;
    }

    @Override
    public String getName() {
        return CliCommands.BUILD;
    }

    @Override
    public void setParentCmdParser(JCommander parentCmdParser) {
    }

    //todo: implement this method properly
    private void init(String projectName, String configPath, String deploymentConfig) {
        try {
            Path configurationFile = Paths.get(configPath);

            if (Files.exists(configurationFile)) {
                Config config = TOMLConfigParser.parse(configPath, Config.class);
                CmdUtils.setConfig(config);
            } else {
                logger.error("Configuration: {} Not found.", configPath);
                throw new CLIInternalException("Error occurred while loading configurations.");
            }
            if (deploymentConfig != null) {
                Path deploymentConfigFile = Paths.get(deploymentConfig);
                if (Files.exists(deploymentConfigFile)) {
                    CmdUtils.createDeploymentConfig(projectName, deploymentConfig);
                }
            }
            String deploymentConfigPath = CmdUtils.getDeploymentConfigLocation(projectName);
            ContainerConfig containerConfig = TOMLConfigParser.parse(deploymentConfigPath, ContainerConfig.class);
            CmdUtils.setContainerConfig(containerConfig);

            CodeGenerationContext codeGenerationContext = new CodeGenerationContext();
            codeGenerationContext.setProjectName(projectName);
            CmdUtils.setCodeGenerationContext(codeGenerationContext);

            initTarget(projectName);
        } catch (ConfigParserException e) {
            logger.error("Error occurred while parsing the configurations {}", configPath, e);
            throw new CLIInternalException("Error occurred while loading configurations.");
        } catch (IOException e) {
            throw new CLIInternalException("Error occurred while reading the deployment configuration", e);
        }
    }

    /**
     * Initializes the project build target directory.
     *
     * @param projectName Name of the micro gateway project.
     * @throws IOException Error occurred while creating target directory structure.
     */
    private void initTarget(String projectName) throws IOException {
        String projectDir = CmdUtils.getProjectDirectoryPath(projectName);
        String targetDirPath = projectDir + File.separator + CliConstants.PROJECT_TARGET_DIR;
        CmdUtils.createDirectory(targetDirPath, true);

        String targetGenDir = targetDirPath + File.separator + CliConstants.PROJECT_GEN_DIR;
        CmdUtils.createDirectory(targetGenDir, true);
        
        //Initializing the ballerina project.
        CommandUtil.initProject(Paths.get(targetGenDir));
        updateProjectOrganizationName(projectName);
        String projectModuleDir = CmdUtils.getProjectTargetModulePath(projectName);
        CmdUtils.createDirectory(projectModuleDir, true);
    }

    /**
     * Updates the organization name created in the Ballerina.toml file with value "wso2".
     *
     * @param projectName Name of the micro gateway project.
     * @throws IOException Error occurred while updating ballerina toml file.
     */
    private void updateProjectOrganizationName(String projectName) throws IOException {
        String ballerinaTomlFile = CmdUtils.getProjectTargetGenDirectoryPath(projectName) + File.separator
                + CliConstants.BALLERINA_TOML_FILE;
        String fileContent = CmdUtils.readFileAsString(ballerinaTomlFile, false);
        fileContent = fileContent.replaceFirst("org-name=.*\"", "org-name= \"wso2\"");
        Files.write(Paths.get(ballerinaTomlFile), fileContent.getBytes(StandardCharsets.UTF_8));
    }
}
