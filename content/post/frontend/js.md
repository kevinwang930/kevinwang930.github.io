---
title: "JavaScript语言概述"
date: 2024-04-14T16:48:11+08:00
categories:
- category
- subcategory
tags:
- tag1
- tag2
keywords:
- tech
#thumbnailImage: //example.com/image.jpg
---
作为后端开发，习惯了规范的静态语法规则，常常诧异于JavaScript的随意与混乱。
写篇文章记录JavaScript的特性以及在后端和浏览器中的使用方式
<!--more-->


# ECMAScript

Ecma international is a Swiss based non-for-profit association. 
Ecma Script is a scripting language specification on which JavaScript is based. Ecma international is in charge of standardizing ECMAScript.
Ecma Script 6th version(ES6) published in 2015. since then Ecma Script specification released every year. Nodejs, firefox and Chrome all support newest features.


## Modules

```
ImportDeclaration   =   import ImportClause FromClause;
                        | import ModuleSpecifier

ImportClause        =   ImportedDefaultBinding              // import name from source
                        | NameSpaceImport                   // import * as Api from './api.js'
                        | NamedImports                      // import { ImportsList }


FromClause          =   from ModuleSpecifier                // " " or  ' '
```


