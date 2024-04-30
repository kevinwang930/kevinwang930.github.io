---
title: "流媒体播放技术鸟瞰"
date: 2024-04-09T19:50:14+08:00
categories:
- stream
tags:
- stream
keywords:
- stream
#thumbnailImage: //example.com/image.jpg
---
本文介绍流媒体播放技术
<!--more-->




# HTTP live streaming (HLS)
HLS is one of the most widely used video streaming protocols. 
Initially developed by Apple, now an open standard.

HLS breaks down video files into smaller downloadable HTTP files and delivers them using HTTP protocol



# MPEG-DASH

MPEG-DASH is a way of delivering data over the internet so that displaying the data before it fully loads.
MPEG-DASH is a streaming method. DASH stands for "Dynamic Adaptive Streaming over HTTP"
MPEG-DAsh is similar to HLS, another streaming protocol, in that it breaks videos down into smaller chunks and encodes those chunks at different quality levels.

# WebRTC

Web real-time communication is a free and open source project providing web browsers and mobile applications with real time communication via APIS.

WebRTC is implemented by browser without traditional server.

# RTSP
Real-Time Streaming Protocol is an application-level network protocol designed for multiplexing and packetizing multimedia transport streams over a suitable transport protocol.
RTSP became public standard in 1998. RTSP 2.0 published as RFC in 2016.


# RTMP
Real-Time Messaging Protocol is a communication protocol for streaming audio, video and data over the internet. 



# open source project

## Ant media server
Live streaming engine software implemented in java, video on demand is also supported

## NodeTube
open source youtube alternative implemented in js

## owncast
streaming + chat implemented in js and go

## opencast
video capture and distribution at scale, implemented in java

## red5
open source stream server that write in java








# Reference

[Multimedia Communications](https://ayomenulisfisip.wordpress.com/wp-content/uploads/2018/01/multimedia-communications.pdf)