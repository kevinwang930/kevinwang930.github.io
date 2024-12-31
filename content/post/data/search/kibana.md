---
title: "Kibana"
date: 2024-12-30T09:38:33+07:00
categories:
- data
- search
tags:
- data
- search
keywords:
- kibana
#thumbnailImage: //example.com/image.jpg
---
Kibana is a browser based analytics and search dashboard for ElasticSearch

<!--more-->

# Kibana logs
filed starts with `_` is reserved filed that may not be searched.
`_source` is the reserved filed contains the original documents.

## KQL

Kibana query language syntax

### terms query

Terms query matches documents that contains one or more exact terms in a field. Use nested filed notation if needed.
```
term_name: content
term_name: "exact match"
nest1.nest2: "content1"
``` 
### boolean query
`or`,`and`,`not` are supported,`and` has higher precedence.
 group operators in parenthesis to override default precedence.

```
response:200 and extension:php
tags: (success and info)
```

### Range query
KQL support `>`,`<`,`=` on numeric and date types.
```
account_number > 200
@timestamp < "2024-12"

```
### wildcard query

```
field: *
field: win*
machine.os*.label:content
```

### nested query

`nested` type is a specialized version of the `object` data type that allows array of of objects to be indexed in a way that can be queried independently of each other.

ElasticSearch has no concept of inner objects, it flatten object hierarchies into a simple list of filed names and values.

```
items: {filed1:content and number > 10}
```