---
title: "Document Object Model - DOM"
date: 2024-04-14T12:40:20+08:00
categories:
- frontend
- dom
tags:
- frontend
- dom
keywords:
- dom
#thumbnailImage: //example.com/image.jpg
---
Document Object Model 作为网页文档编程接口标准，不管是在原生JS，react或者是vue中对网页的修改最终都是通过浏览器的DOM接口完成的。
本文记录dom的定义及接口规范。
<!--more-->

The Document Object Model(DOM) is a application interface for web documents. It represents the page so that programs can change the document structure, style and content.
A web page is a document that can be either displayed in the browser window or as the HTML source. In both cases, it is the same document but the DOM representation allows it to be manipulated.
DOM was designed to be independent of any particular programming language, making the structure representation of the document available from a single,consistent API.

DOM contains 2 parts:
DOM core represents the functionality used for XML doocuments, also serves as basis for DOM HTML

# DOM Core

`EventTarget` object represents a target to which an event can be dispatched when something happened.

`Node` every object loaded within a document is a node of some kind. In an HTML document, an object can be an element node but also a `Text` node or `Attr` node.

`Element` is based on `Node`. It refers to an element or node of type `Element` returned by a member of DOM api. 

`Document` interface represents any web page loaded in the browser and serves as an entry point into the web page's content, which is the DOM tree.



# DOM HTML

DOM HTML add functionalities based on the DOM CORE.

most of the html elements we used in html are defined in the DOM HTML standard. blow list some of them.

```
HTMLTableElement
HTMLHeadElement
HTMLFormElement
HTMLLinkElement
```

```plantuml

interface Event {
    DOMString type
    EventTarget? target
    EventTarget? srcElement
    EventTarget? currentTarget
    boolean bubbles
    boolean cancelable
    boolean composed
    boolean defaultPrevented
    initEvent()
    sequence<EventTarget> composedPath()
    stopPropagation()
    
}
interface EventTarget {
    addEventListener()
    removeEventListener()
    dispatchEvent()

}


interface Node extends EventTarget {
    DOMString nodeName
    DOMString nodeValue
    unsigned short nodeType
    Node  parentNode
    NodeList  childNodes
    Node    firstChild
    Node lastChild
    Node previousSibling
    Node nextSibling
    NamedNodeMap attributes
    Document ownerDocument
    insertBefore()
    replaceChild()
    removeChild()
    appendChild()
    hasChildNodes()
    cloneNode()
}
interface Element extends Node {
    DOMString tagName
    getAttribute()
    setAttribute()
    removeAttribute()
    getAttributeNode()
    setAttributeNode()
    removeAttributeNode()
    getElementByTagName()
}
interface NodeList {
    Node item
    unsigned long length
}
interface Attr extends Node {
    DOMString name
    boolean specified
    DOMString value
}

interface CharacterData extends Node {
    DOMString data
    unsigned long length
    substringData()
    appendData()
    insertData()
    deleteData()
    replaceData()
}
interface Text extends CharacterData {
}
interface NameNodeMap
interface Document extends Node {
    DocumentType doctype
    DOMImplementation implementation
    Element documentElement
    createElement()
    createTextNode()
    createAttribute()
    getElementsByTagName()
    createDocumentFragment()
}

interface HTMLDocument extends Document {
    DOMString title
    DOMString referrer
    DOMString domain
    DOMString URL
    HTMLElement body
    HTMLCollection images
    HTMLCollection applets
    HTMLCollection links
    HTMLCollection forms
    HTMLCollection anchors
    HTMLCollection cookie
    open()
    close()
    write()
    getElementById()
    getElementsByName()
}

interface HTMLElement extends Element {
    DOMString id
    DOMString title
    DOMString lang
    DOMString dir
    DOMString className
}



interface DocumentFragment extends Node
NodeList *-right- Node
Element *-- Attr
Document *-- DocumentFragment
EventTarget -right-> Event:dispatch
```


# JavaScript and DOM

In JavaScript which is inline in a `<script>` element or included in the webpage, DOM API can be used directly through the `document` or `windows` objects to manipulate the document itself.



# reference

Web Hypertext Application Technology Working Group standard [https://dom.spec.whatwg.org/#concept-event-dispatch](https://dom.spec.whatwg.org/#concept-event-dispatch)