---
title: "Java Nio"
date: 2024-02-24T16:11:41+08:00
categories:
- java
- nio
tags:
- netty
- java
- nio
keywords:
- tech
#thumbnailImage: //example.com/image.jpg
---

# Java NIO

## 1. stream api
```plantuml
package io {
class InputStream {
    read(byte[])
    mark(int)
    close()
    reset()
    skip()
}
class OutputStream() {
    write(byte[])
    flush()
    close()
}
}

package nio() {
    interface Channel {
        close()
        isOpen()
    }
    abstract class FileChannel {
        open(Path)
        read(ByteBuffer)
        write(ByteBuffer)
        lock()
        close()
    }

    Channel o-- FileChannel
}

```

## netty

### event loop
1. i/o processor
2. custom task
### channel
wrapper of socket
1. channel pipeline
2. channel handler
