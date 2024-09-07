---
title: "Lucene internals"
date: 2024-08-31T19:09:15+08:00
categories:
- data
- search
tags:
- lucene
keywords:
- lucene
#thumbnailImage: //example.com/image.jpg
---

This article introduces Lucene internals 
<!--more-->

Apache Lucene is a java full-text search engine. Lucene provide its core library and API that can easily be used to add search capabilities to applications.


# API
Lucene is divided into several packages:
* `analysis` defines an abstract `Analyzer` API for converting text from a `Reader` into a `TokenStream`. A TokenStream can be composed by applying `TokenFilters` to the output of a `Tokenizer`. `Tokenizer` and `TokenFilters` are strung together and applied with an `Analyzer`.
* `analysis-common` provides a number of Analyzer implementations.
* `codecs` provides an abstraction over the encoding and decoding of the inverted index structure, as well as different implementations that can be chosen depending upon application needs.
* `document` provides a simple `Document` class. A document is a set of named `Field`s, whose values may be strings or instances of `Reader`.
* `index` provide two primary classes: `IndexWriter`, which creates and adds documents to indices; and `IndexReader` which accesses data in the index.
* `search` provides data structures to represent queries(`TermQuery` for individual words, `PhraseQuery` for phrases, `BooleanQuery` for boolean combinations of queries) and the `IndexSearcher` which turns queries into `TopDocs` . A number of `QueryParser`s are provided for producing query structures from strings or xml.
* `store` defines an abstract class for storing persistent data, the `Directory` which is a collection of named files written by an `IndexOutput` and read by `IndexInput`. Multiple implementations are provided, but `FSDirectory` is generally recommended as it tries to use operation system disk buffer caches efficiently.

typical usage
1. Create `Documents` by adding `Field`s.
2. Create an `IndexWriter` and add documents to it with `addDocument()`
3. Call `QueryParser.parse()` to build a query from a string
4. Create an `IndexSearcher` and parse the query to its `search()` method.

# Lucene






