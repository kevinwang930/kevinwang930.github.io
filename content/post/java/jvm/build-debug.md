---
title: "OpenJDK build and debug"
date: 2025-03-12T01:22:42+07:00
draft: true
categories:
- java
- jvm
tags:
- jvm
keywords:
- jvm
#thumbnailImage: //example.com/image.jpg
---
This article introduces how to build, develop, and debug the OpenJDK source code for both C++ (Hotspot JVM) and Java components.
<!--more-->

# Building OpenJDK

## 1. Prepare
To build OpenJDK, you need a "Boot JDK". This is an already installed JDK of the previous major version (e.g., to build JDK 21, you need JDK 20 or 21).

* Install the required Boot JDK.
* Ensure you have standard build tools installed (e.g., `make`, `gcc`/`clang` or Visual Studio, and `autoconf`).

## 2. Configure the Build
Configure the build system. For debugging, it is recommended to use the `slowdebug` level, which disables compiler optimizations and includes full debug symbols.

```shell
bash configure --with-debug-level=slowdebug
```

Additional useful flags:
* `--with-jtreg=<path-to-jtreg>`: Configures the location of the JTReg regression test harness.
* `--with-boot-jdk=<path-to-boot-jdk>`: Explicitly specifies the Boot JDK path if not auto-detected.

## 3. Run Make
Compile the codebase. The standard target is `images`, which builds a complete JDK distribution.

```shell
make images
```

For faster incremental rebuilds during development, you can use:
```shell
make exploded-image
```

## 4. Verify and Test
Verify that the newly built JDK works:
```shell
./build/*/images/jdk/bin/java -version
```

Run a basic set of tests to ensure stability:
```shell
make test-tier1
```

Reference: [OpenJDK Building Guide](https://openjdk.org/groups/build/doc/building.html)

---

# Developing and Debugging

The OpenJDK codebase contains both C++ (primarily the Hotspot JVM) and Java (the class libraries). Since traditional IDEs rarely support both languages in a single project structure seamlessly, developers configure separate IDE environments for each part of the codebase.

## 1. Developing Java Code (IntelliJ IDEA & Eclipse)
To work with the Java class libraries, use a Java-focused IDE.

### IntelliJ IDEA
OpenJDK provides a script to generate a pre-configured IntelliJ project.
1. Generate the project structure:
   ```shell
   bash bin/idea.sh
   ```
2. Open IntelliJ and select **File -> Open**, then choose the top-level repository directory.
3. Configure the Project SDK by navigating to **File -> Project Structure -> Project** and selecting the built JDK images path:
   ```
   build/<config>/images/jdk
   ```
4. To run and debug Java tests from the IDE, install the **JTReg plugin for IntelliJ**. The plugin instructions are available at the [jtreg IntelliJ plugin repository](https://github.com/openjdk/jtreg/tree/master/plugins/idea).

### Eclipse JDT
Generate an Eclipse Java workspace:
```shell
make eclipse-java-env
```
Import the workspace via **File -> Import -> Projects from Folder or Archive**, selecting the `ide/eclipse` directory within the build output folder.

---

## 2. Developing C++ Code (CLion, VS Code, Visual Studio)
To work with the Hotspot JVM or other native C++ components, use a C++-focused IDE.

### CLion & Compilation Database
CLion and other C++ IDEs support indexing via a standard compilation database (`compile_commands.json`).
1. Generate the compilation database:
   ```shell
   make compile-commands
   ```
   *(Optional)* To generate it only for the Hotspot JVM (which is faster):
   ```shell
   make compile-commands-hotspot
   ```
2. In CLion, select **File -> Open** and choose the generated `compile_commands.json` file. CLion will index the C++ source files based on the exact compile commands used by the build system.
3. Configure custom build/debug targets in CLion to execute `make images` or `make exploded-image` before debugging.

### Visual Studio Code
Generate a VS Code workspace with C++ indexing:
```shell
make vscode-project
```
This creates `jdk.code-workspace` in the build output folder. Open this workspace in VS Code. If using alternative indexers like `clangd` or `ccls`, run:
```shell
make vscode-project-clangd
```

### Visual Studio (Windows)
Generate a Visual Studio solution for the Hotspot JVM:
```shell
make hotspot-ide-project
```
This creates `jvm.vcxproj` in the `ide/hotspot-visualstudio` subfolder of the build output.

---

## 3. Mixed-Language Environments (Eclipse Mixed Nature)
To switch between Java and C++ natures in a single IDE, generate a mixed Eclipse workspace:
```shell
make eclipse-mixed-env
```
Import the resulting project from the `ide/eclipse` directory in the build output folder.

---

## 4. Running and Debugging Tests
Testing is driven by `jtreg` (for Java regression tests) and `gtest` (for C++ unit tests) via the `make test` interface.

### Running Tests via Command Line
```shell
# Run a specific Java test suite using jtreg
make test TEST="jtreg:test/jdk/java/lang/String"

# Run C++ unit tests using gtest
make test TEST="gtest:LogTagSet"

# Run tests against the exploded image for faster cycles
make exploded-test TEST=tier1
```

### Debugging C++ in CLion
To debug the JVM with a Java application:
1. In CLion, create a **Custom Build Application** target.
2. Set the **Executable** to the newly built Java binary: `build/<config>/images/jdk/bin/java`.
3. Set the **Program arguments** to the Java class or JAR you want to run (e.g., `MyProgram`).
4. Set breakpoints in the C++ source files (e.g., in `thread.cpp` or `bytecodeInterpreter.cpp`).
5. Click **Debug**. The IDE will launch the JVM, hit your breakpoints in the C++ code, and allow you to inspect the JVM state.
