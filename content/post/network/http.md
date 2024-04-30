---
title: "HTTP the application-layer protocol"
date: 2024-04-28T15:39:31+08:00
categories:
- network
- http
tags:
- network
- http
keywords:
- http
#thumbnailImage: //example.com/image.jpg
---

HyperText Transfer Protocol(Http) is an application layer protocol for transmitting hypermedia documents. It is commonly used in network communications nowadays.

<!--more-->


HTTP follows a classical client-server model, with client opening a connection to make a request, then waiting until it receives a response. HTTP is a stateless protocol, meaning that server does not keep any data (state) between two requests.


# Method

## Post

HTTP post sends data to the server. The type of the body is indicated by the `Content-type` header.

## content type
### multipart
one or more different sets of data are combined in a single body, a "multipart" Content-Type must appear in the entity's header.


