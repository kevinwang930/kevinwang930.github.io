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


### form-data
An HTML form on a web page is a convenient way to configure an HTTP request to send data to server.
content of http form in packet:
```
GET /?say=Hi&to=Mom HTTP/2.0
Host: foo.com
```
```
POST / HTTP/2.0
Host: foo.com
Content-Type: application/x-www-form-urlencoded
Content-Length: 13

say=Hi&to=Mom
```

### multipart form-data
one or more different sets of data are combined in a single body, a "multipart" Content-Type must appear in the entity's header.

```
POST /foo HTTP/1.1
Content-Length: 68137
Content-Type: multipart/form-data; boundary=---------------------------974767299852498929531610575

-----------------------------974767299852498929531610575
Content-Disposition: form-data; name="description"

some text
-----------------------------974767299852498929531610575
Content-Disposition: form-data; name="myFile"; filename="foo.txt"
Content-Type: text/plain

(content of the uploaded file foo.txt)
-----------------------------974767299852498929531610575--

```

