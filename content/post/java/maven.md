---
title: "java project management - Maven"
date: 2024-08-12T12:04:00+08:00
categories:
- java
- build
tags:
- java
- maven
keywords:
- maven
#thumbnailImage: //example.com/image.jpg
---

This article introduce java project management and comprehension tool - Maven
<!--more-->

Based on the concept of project object Model (POM), Maven can manage a project's build, reporting and documentation from a central piece of information.

# Build LifeCycle

Maven build is based around the concept of build lifecycle, which means the process for building and distributing a particular artifact(project) is clearly defined.

There are 3 built-in build lifecycles:
1. `default` handles your project deployment
2. `clean` handles project cleaning
3. `site` handles the creation of project's web site

## phase
Each build lifecycle is defined by a different list of build phases, a build phase represents a stage in the lifecycle.

The `default` build lifecycle: 
1. validate
2. initialize
3. generate-sources
4. process-sources
5. generate-resources
6. process-resources
7. compile
8. process-classes   post-process the generated files from compilation, for example to do bytecode enhancement on java classes.
9. test-compile
10. test
11. package
12. verify
13. install
14. deploy



# Plugin

Maven is a plugin execution framework, all work is done by plugins.

Core plugins:
* clean
* compiler
* deploy
* install
* surefire     run the junit tests in an isolated classloader


## plugin goals

A build phase is made up of plugin goals.
In pom declaring the plugin goals bound to the build phase to carry out the responsibility

* show all goals of a plugin
    ```
    mvn help:describe -Dplugin=versions
    ```


## Maven Dependency plugin

The dependency plugin provides the capability to manipulate artifacts

## Versions Maven Plugin

manage the versions of artifacts in a project's POM

* update project version
    ```
    mvn build-helper:parse-version versions:set -DnewVersion=\${parsedVersion.majorVersion}.\${parsedVersion.minorVersion}.\${parsedVersion.nextIncrementalVersion} versions:commit
    ```
