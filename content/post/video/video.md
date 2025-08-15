---
title: "Video Basics"
date: 2024-04-22T14:32:16+08:00
draft: true
categories:
- video
tags:
- video
keywords:
- video
#thumbnailImage: //example.com/image.jpg
---
This article introduces video basics
<!--more-->


# image

## color

in common gray color pixel images, each pixel has 8 bits to store the color info, total 256 colors.

### RGB color
in RGB  each channel has 8 bits, so total 24 bits.

# video




## codec
A codec(coder/decoder) is a method for compressing and decompressing data so that it can be easily transported and received by different applications.

### video encoding
Video encoding is the process of turning uncompressed video input into a form that can be stored and played by a variety of devices. Video encoding involves two main processes: compression and transcoding.

Compression significantly decreases the size of the video file.

Transcoding refers to the total audio and video conversion process from one video format to another.




## container

A container combines an encoded audio stream, encoded video stream, and metadata in a single video file. 

The metadata tells the video player how to coordinate different audio and video codecs and may also provide additional elements, such as subtitles or alternate audio streams. 

Each container supports a different range of video codecs. 

Often, video file extensions are named for the containers they use, (MP4 video file is really an MP4 container). A video file can only play properly if both the codec and container are compatible with the video player.

### video formats


#### MPEG

MPEG is the moving picture experts group, working under the joint direction of ISO and IEC.

MPEG standards specify only syntax and semantics of the bit-streams and the decoding process. They do not specify the coding process.

#### MPEG-1 
MPEG-1 is restricted to non-interlaced video formats and is primarily intended to support video coding at bit-rates up to about 1.5Mbit/s.
MPEG-1 provides support for full motion video playback from CD

#### MPEG-2 
MPEG-2 is capable of coding interlaced pictures directly.
Interlaced picture is a method of encoding a bitmap image such that a person who has partially received it sees a degraded copy of the entire image.


1. bit-rates   
   1. common                5-10  Mbit/s
   2. high definition       15-30 Mbit/s

#### MPEG-4
MPEG-4 aimed at encoding video at lower bit rates and higher video qualities than MPEG-2, creating a multimedia transmission and storage framework.
MPEG-4 became an international standard in 1999.

##### H.264

Advanced Video Coding(AVC), also called H.264 or MPEG-4 part 10, is the most common video compression standard in use today.

#### MPEG-H
A group of standards under development by MPEG, it has various parts, each of which can be considered a separate standard.
1. media transport protocol standard
2. video compression standard   HEVC(High efficiency video coding) H.265
3. audio compression standard
4. digital file format container standard

#### MP3
formally MPEG-1 audio layer III or MPEG-2 audio layer III is a coding format is a coding format for digital audio. Originally defined as the third audio format of the MPEG-1 standard, it was retained and further extended as the third audio format of the subsequent MPEG-2 standard.

MP3 as a file format commonly designates files containing an elementary stream of MPEG-1 audio or MPEG-2 Audio encoded data.
MP3 uses lossy data compression to encode data.


### M3U
(MP3 URL or Moving Picture Experts Group Audio layer 3 Uniform Resource Locator) is a computer file format for a multimedia playlist.

Although originally designed for audio files, it is commonly used to point media players to audio and video resources.




#### MP4

MP4 refers to the digital container file that cats as a wrapper around the video.
The full name of the MP4 standard is MPEG-4 Part 14, MP4 is the digital container file and MPEG-4 is the standard for encoding the video content within MP4 files.
Apple developed similar proprietary file format MOV


#### M4V

M4V file format is a video container format developed by Apple and is very similar to the MP4 format.
The primary difference is that m4v files may optionally be protected by DRM copy protection.

#### WebM
 WebM is an open sourced audiovisual media format, it has sister project, webP for images.

#### AVI
Audio Video Interleave is a video format created by Microsoft. one of the oldest video file container specifications.

#### FLV
Flash video Format created by Adobe Flash. 


