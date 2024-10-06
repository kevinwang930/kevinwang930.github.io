---
title: "FFMPEG And It's Java Binding JavaCV"
date: 2024-04-22T13:11:20+08:00
categories:
- video
- ffmpeg
tags:
- video
- ffmpeg
keywords:
- ffmpeg
#thumbnailImage: //example.com/image.jpg
---
This Article introduces ffmpeg and it's java binding JavaCV
<!--more-->

# Concept and Structure


``` plantuml
title: transcoding process
rectangle "input file" as input
rectangle encoded [encoded data
packets]
rectangle decoded [decoded
frames]
rectangle encoded_data [encoded data
packets]
rectangle output [output 
file]
input -right-> encoded: demuxer
encoded-right-> decoded: decoder
decoded -down-> encoded_data: encoder
encoded_data -left-> output: muxer

```

## library

`libavformat` library provides a generic framework for multiplexing and demultiplexing (muxing and demuxing) audio,video and subtitle streams. It encompasses multiple muxers and demuxers for multimedia container formats.

`libavcodec` library provides a generic encoding/decoding framework and contains multiple decoders and encoders for audio,video and subtitle streams, and several bitstream filters

`libavdevice` library provides a generic framework for grabbing from and rendering to many common multimedia input/output devices

`libavfilter` library provides a generic audio/video filtering framework containing several filters , sources and sinks.

`libswscale` library performs highly optimized image scaling and colorspace and pixel format conversion operations

`libswresample` library performs highly optimized audio resampling, rematrixing and sample format conversion operations.


### liaavformat



`AVFormatContext` format I/O context

`AVFrame` describes decoded (raw) audio or video data

`AVPacket` stores compressed data. It is typically exported by demuxers and then passed as input to decoders.
For video, it should typically contain one compressed frame. For audio it may contain several compressed frames.


`pts` presentation timestamp
`dts` decompression timestamp

```plantuml
struct AVFormatContext {
    AVInputFormat *iformat
    AVOutputFormat *oformat
    AVIOContext *pb
    unsigned int nb_streams
    AVStream **streams
    char *url
    AVCodecID video_codec_id
    AVCodecID audio_codec_id
}

struct AVStream {
    int index
    int id
    AVCodecParameters *codecpar
    AVRational time_base
    int64_t start_time
    int64_t duration
    AVPacket attached_pic
}

struct AVCodecParameters {
    AVMediaType codec_type
    AVCodecID   codec_id
    uint8_t *extradata
    int      extradata_size
    int format
}

struct AVFrame {
    uint8_t *data[AV_NUM_DATA_POINTERS]
    int linesize[AV_NUM_DATA_POINTERS]
    uint8_t **extended_data
    int width
    int height
    int nb_samples
    int format
    int64_t pts
    int quality
    int repeat_pict
    int sample_rate
    AVBufferRef *buf[AV_NUM_DATA_POINTERS]
    AVDictionary *metadata
    AVChannelLayout ch_layout
    int64_t duration
}

struct   AVPacket {
    AVBufferRef *buf
    int64_t pts
    int64_t dts
    uint8_t *data
    int   size
    int   stream_index
    AVPacketSideData *side_data
    int64_t duration
    AVRational time_base
}  

AVFormatContext *-- AVStream
AVPacket *-- AVFrame
AVStream *-- AVCodecParameters
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



## input/output
```
ffmpeg -i input.avi output.mp4
```



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
