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



``` plantuml
title: transcoding process
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

```plantuml
title: complex filter graphs
left to right direction
rectangle input0 [input 0
]
rectangle input1 [input 1
]
rectangle input2 [input 2
]

rectangle graph [complex
filter
graph
]

rectangle output0 [output 0
]
rectangle output1 [output 1
]

input0 --> graph
input1 --> graph
input2 --> graph
graph --> output0
graph --> output1
```

# command line
```
ffmpeg [global_options] {[input_file_options] -i input_url} ... {[output_file_options] output_url} ...
```



## input
```
ffmpeg -i input.avi output.mp4
```

## output

## stream selection
ffmpeg provides the `-map` option for manual control of the stream selection in each output file. if no map options are set, ffmpeg select streams automatically.

stream index matches the stream with the index.
stream type for the type of the stream 
```
    v for video
    a for audio
    s for subtitle
    d for data
    t for attachment
```


```
ffmpeg -i A.avi -i B.mp4 out1.mkv out2.wav -map 1:a -c:a copy out3.mov
```

## codec selection
select an encoder (before output file) or a decoder(before input file) for one or more streams.
`codec` is the name of the decoder/encoder or `copy` to indicate the stream is not to be re-encoded.

```
-c[:stream_specifier] codec (input/output,per-stream)
-codec[:stream_specifier] codec (input/output,per-stream)
```











```
-c[:stream_specifier] codec (input/output,per-stream)
-codec[:stream_specifier] codec (input/output,per-stream) 
```
