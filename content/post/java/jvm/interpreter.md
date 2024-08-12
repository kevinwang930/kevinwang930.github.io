---
title: "JVM ByteCode Interpreter"
date: 2024-08-12T15:49:03+08:00
categories:
- java
- jvm
tags:
- jvm
- interpreter
keywords:
- interpreter
#thumbnailImage: //example.com/image.jpg
---
This article describes JVM ByteCode Interpreter
<!--more-->

```plantuml

class templateInterpreter {
    DispatchTable _active_table
    DispatchTable _normal_table
}

class DispatchTable {
address _table[number_of_states][length]
}

class TemplateTable {
    Template _template_table[]
    Template _template_table_wide[]
    InterpreterMacroAssembler* _masm
    void Initialize()
}

class Template {
    int       _flags
    TosState  _tos_in
    TosState  _tos_out
    generator _gen
    int       _arg
}

TemplateTable --> Template : generate
templateInterpreter *-- DispatchTable
DispatchTable -right-> Template: entry

```

