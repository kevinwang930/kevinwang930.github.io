---
title: "Socket"
date: 2024-08-02T13:48:50+08:00
categories:
- network
- socket
tags:
- socket
- netty
keywords:
- socket
#thumbnailImage: //example.com/image.jpg
---
本文介绍Socket
<!--more-->


# Socket

A network Socket is a software structure within a network node of a computer network that serves as an endpoint for sending and receiving data across the network.

Because the standardization of the `TCP/IP` protocol in the development of the Internet, the term network socket is most commonly used int the context of the Internet protocol suite, and is therefore often also referred to as `Internet socket`. In this context, a socket is externally identified to other hosts by its socket address(transport protocol, ip address and port number).


A protocol stack, usually provided by the operating system, is a set of services that allow processes to communicate over network using the protocols that the stack implements.


The application programming interface(API) that programs use to communicate with the protocol stack, using network sockets, is called a `socket API`. Development of application programs that utilize this API is called `Socket Programming`.


## Socket Port

Generally port 0 - 1023 is reserved port.
Ephemeral port range  used for client socket local port. 
Ephemeral port range can be checked by 
```
sysctl -a | grep net.ipv4.ip_local_port linux
sysctl -a | grep ip.portrange    mac
```

