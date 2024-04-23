---
title: "FFMPEG功能介绍"
date: 2024-04-22T13:11:20+08:00
categories:
- stream
- ffmpeg
tags:
- stream
- ffmpeg
keywords:
- ffmpeg
#thumbnailImage: //example.com/image.jpg
---
FFMPEG 流行的多媒体处理框架，提供了编解码、转码 、混流、解混、流传输、过滤和播放等功能，支持格式广， 可移植性高。 


<!--more-->

# FFMPEG tools

```
ffmpeg [global_options] {[input_file_options] -i input_url} ... {[output_file_options] output_url} ...
```

## transcoding process

```plantuml
rectangle "input file" as input
rectangle encoded [encoded data
packets]
rectangle decoded [decoded
frames]
rectangle encoded_data [encoded dta
packets]
rectangle output [output 
file]
input -right-> encoded: demuxer
encoded-right-> decoded: decoder
decoded -down-> encoded_data: encoder
encoded_data -left-> output: muxer

```

## video play
```
ffplay target.file
```

## video slicing



