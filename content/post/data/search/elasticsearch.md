---
title: "Elasticsearch generals"
date: 2026-05-01T20:55:22+02:00
categories:
- data
- search
tags:
- data
- search
keywords:
- elasticsearch
#thumbnailImage: //example.com/image.jpg
---
This article introduces general concept of Elastic search.
<!--more-->

ElasticSearch is a distributed, open-source search and analytics engine built on Apache lucene


# Common  APIs
Elasticsearch exposes a RESTful HTTP API. 
## Document APIs
* `POST /{index}/_doc` index a document
* `GET /{index}/_doc/{id}` get a document
* `DELETE /{index}/_doc/{id}` delete a document
* `POST /{index}/_update/{id}` update a document
* `POST /{index}/_bulk` execute bulk operations
* `GET /{index}/_count` count documents in an index
* `GET /{index}/_search` search documents
* `POST /{index}/_search` search with a request body
* `POST /_msearch` multi-search across one or more indices
* `POST /_update_by_query` update matching documents by query
* `POST /_delete_by_query` delete matching documents by query
* `GET /{index}/_termvectors` retrieve term vectors for a document

## Index APIs
* `PUT /{index}` create an index
* `DELETE /{index}` delete an index
* `GET /{index}` get index information
* `HEAD /{index}` check whether an index exists
* `GET /{index}/_mapping` get index mapping
* `PUT /{index}/_mapping` update index mapping
* `GET /{index}/_settings` get index settings
* `PUT /{index}/_settings` update index settings
* `POST /{index}/_refresh` refresh index
* `POST /{index}/_flush` flush index
* `POST /{index}/_forcemerge` force merge index segments
* `POST /{index}/_open` open an index
* `POST /{index}/_close` close an index

## Cluster APIs
* `GET /_cluster/health` get cluster health
* `GET /_cluster/stats` get cluster metrics
* `GET /_cluster/state` get cluster state
* `GET /_cluster/settings` get cluster settings
* `PUT /_cluster/settings` update cluster settings
* `GET /_nodes` get node information
* `GET /_nodes/stats` get node statistics
* `GET /_nodes/hot_threads` show hot threads on nodes
* `GET /_cluster/pending_tasks` list pending cluster tasks

## Cat APIs
* `GET /_cat/health?v` cluster health in a compact format
* `GET /_cat/indices?v` list indices
* `GET /_cat/nodes?v` list nodes
* `GET /_cat/shards?v` list shards
* `GET /_cat/allocation?v` show shard allocation
* `GET /_cat/recovery?v` show recovery status
* `GET /_cat/pending_tasks?v` show pending tasks
* `GET /_cat/templates?v` list index templates

## Snapshot and restore APIs
* `PUT /_snapshot/{repository}/{snapshot}` create a snapshot
* `GET /_snapshot/{repository}/{snapshot}` get snapshot information
* `DELETE /_snapshot/{repository}/{snapshot}` delete a snapshot
* `POST /_snapshot/{repository}/{snapshot}/_restore` restore a snapshot

## Reindexing and scroll APIs
* `POST /_reindex` copy documents from one index to another
* `GET /_search/scroll` retrieve the next scroll page
* `DELETE /_search/scroll` clear scroll contexts

## Reference
[API DOCS](https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-get)



# Mapping
Schema definition specifying how document fields are stored and indexed in Elasticsearch.


# search

Elasticsearch search requests use JSON bodies to specify query logic, pagination, sorting, aggregations, and result shaping. Common fields in the search JSON include:

* `query` - selects documents.
  * `bool` - combine clauses: `must`, `should`, `must_not`, `filter`
  * `match` - full-text match on analyzed fields
  * `term` - exact value match
  * `range` - numeric or date intervals
  * `nested` - queries inside nested object fields
  * `exists` - field presence
* `aggs` / `aggregations` - summarize matching documents.
  * bucket aggs: `terms`, `range`, `date_histogram`, `histogram`, `filters`
  * metric aggs: `avg`, `sum`, `min`, `max`, `stats`, `cardinality`, `value_count`
* `size` - hits per page
* `from` - result offset for pagination
* `sort` - result ordering by field or score
* `_source` - which document fields to return
* `fields` - stored/scripted field values to fetch
* `highlight` - return matched snippets
* `post_filter` - filter search hits after aggregations
* `timeout` - time limit for the search
* `track_total_hits` - accurate hit count control
* `explain` - return scoring explanation for each hit
* `track_scores` - keep scores when sorting/paging
* `profile` - return query execution timing
* `search_after` - deep pagination cursor using sort values
* `collapse` - collapse results by a field value
* `suggest` - autocomplete or correction suggestions
* `script_fields` - compute extra fields per hit with scripts
* `rescore` - rerank top hits with a second query

These fields can be combined to express complex search behavior.

