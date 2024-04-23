---
title: "流媒体播放技术鸟瞰"
date: 2024-04-09T19:50:14+08:00
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
本文介绍流媒体播放技术
<!--more-->



# MPEG

MPEG is the moving picture experts group, working under the joint direction of ISO and IEC.

MPEG standards specify only syntax and semantics of the bit-streams and the decoding process. They do not specify the coding process.

## MPEG-1 
MPEG-1 is restricted to non-interlaced video formats and is primarily intended to support video coding at bit-rates up to about 1.5Mbit/s.
MPEG-1 provides support for full motion video playback from CD

## MPEG-2 
MPEG-2 is capable of coding interlaced pictures directly.
Interlaced picture is a method of encoding a bitmap image such that a person who has partially received it sees a degraded copy of the entire image.


1. bit-rates   
   1. common                5-10  Mbit/s
   2. high definition       15-30 Mbit/s

## MP3
formally MPEG-1 audio layer III or MPEG-2 audio layer III is a coding format is a coding format for digital audio. Originally defined as the third audio format of the MPEG-1 standard, it was retained and further extended as the third audio format of the subsequent MPEG-2 standard.

MP3 as a file format commonly designates files containing an elementary stream of MPEG-1 audio or MPEG-2 Audio encoded data.
MP3 uses lossy data compression to encode data.


### M3U
(MP3 URL or Moving Picture Experts Group Audio layer 3 Uniform Resource Locator) is a computer file format for a multimedia playlist.

Although originally designed for audio files, it is commonly used to point media players to audio and video resources.




## MP4

MP4 refers to the digital container file that cats as a wrapper around the video.
The full name of the MP4 standard is MPEG-4 Part 14, MP4 is the digital container file and MPEG-4 is the standard for encoding the video content within MP4 files.
Apple developed similar proprietary file format MOV


## M4V

M4V file format is a video container format developed by Apple and is very similar to the MP4 format.
The primary difference is that m4v files may optionally be protected by DRM copy protection.

## WebM
 WebM is an opensourced audiovisual media format, it has sister project, webP for images.




# HTTP live streaming (HLS)
HLS is one of the most widely used video streaming protocols. 


# MPEG-DASH

MPEG-DASH is a way of delivering data over the internet so that displaying the data before it fully loads.
MPEG-DASH is a streaming method. DASH stands for "Dynamic Adaptive Streaming over HTTP"
MPEG-DAsh is similar to HLS, another streaming protocol, in that it breaks videos down into smaller chunks and encodes those chunks at different quality levels.




# Reference

[Multimedia Communications](https://ayomenulisfisip.wordpress.com/wp-content/uploads/2018/01/multimedia-communications.pdf)