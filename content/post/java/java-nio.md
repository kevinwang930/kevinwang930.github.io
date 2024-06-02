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
本文记录java Nio的接口与实现
<!--more-->

`Channel`  a nexus for I/O operations, it represents an open connection to an entity such as a hardware device, a file , a network socket and so on.

`SelectableChannel`  A Channel that can be multiplexed via a `Selector`

`Selector` A multiplexor of `SelectableChannel` objects

`SelectorProvider` Service-Provider class for selectors and selectable channels

`KQueue` I/O event notification systems used mainly on FreeBSD and macOS.  
  
`epoll` similar event notification system used primarily on Linux

```plantuml

interface Channel {
    boolean isOpen()
    void close()
}



interface NetworkChannel extends Channel {
    NetworkChannel bind(SocketAddress local)
    SocketAddress getLocalAddress()
}


abstract class  SelectorProviderImpl extends SelectorProvider


abstract class SelectableChannel  {
    abstract SelectorProvider provider()
    abstract SelectionKey keyFor(Selector sel)
    abstract boolean isRegistered()
    abstract SelectionKey register(Selector sel, int ops, Object att)
    abstract boolean isBlocking()
    abstract Object blockingLock()
}
abstract class AbstractSelectableChannel extends SelectableChannel {
    SelectorProvider provider
    SelectionKey[] keys
    Object keyLock
    Object regLock


}

abstract class Selector implements Closeable {
     static Selector open()
     abstract boolean isOpen()
     abstract SelectorProvider provider()
     abstract Set<SelectionKey> keys()
     abstract Set<SelectionKey> selectedKeys()
     abstract int select()
     abstract Selector wakeup()
     abstract void close()
}

abstract class SelectorProvider {
    static SelectorProvider provider()
    abstract DatagramChannel openDatagramChannel()
    abstract Pipe openPipe()
    abstract AbstractSelector openSelector()
    abstract ServerSocketChannel openServerSocketChannel()
    abstract SocketChannel openSocketChannel()
}


    abstract class FileChannel {
        open(Path)
        read(ByteBuffer)
        write(ByteBuffer)
        lock()
        close()
    }

    class SocketChannelImpl extends SocketChannel implements SelChImpl {
        FileDescriptor fd
        ReentrantLock readLock
        ReentrantLock writeLock
        Object stateLock
        volatile int state
        long readerThread
        long writerThread
        SocketAddress localAddress
        SocketAddress remoteAddress
        Socket socket
    }

    abstract class AbstractSelector extends Selector {
        SelectorProvider provider
        Set<SelectionKey> cancelledKeys
    }

    abstract class SelectorImpl extends AbstractSelector {
        Set<SelectionKey> keys
        Set<SelectionKey> selectedKeys
        Set<SelectionKey> publicKeys
        Set<SelectionKey> publicSelectedKeys
        Deque<SelectionKeyImpl> cancelledKeys

    }

    class KQueueSelectorImpl extends SelectorImpl {
        int kqfd
        long pollArrayAddress
        native int create()
        native int register(int kqfd, int fd, int filter, int flags)
        native int poll(int kqfd, long pollAddress, int nevents, long timeout)
    }

    abstract class SocketChannel extends  AbstractSelectableChannel implements NetworkChannel

    class KQueueSelectorProvider extends SelectorProviderImpl

    Channel o-- FileChannel
    Selector *-left- SelectorProvider
    Selector -down-> SelectableChannel : select

    Channel <|-- SelectableChannel
KQueueSelectorProvider --> KQueueSelectorImpl: provide

```



## netty

### event loop
1. i/o processor
2. custom task
### channel
wrapper of socket
1. channel pipeline
2. channel handler
