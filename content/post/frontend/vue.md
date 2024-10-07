---
title: "前端框架-Vue"
date: 2024-04-13T20:38:59+08:00
categories:
- frontend
- vue
tags:
- frontend
- vue
keywords:
- vue
#thumbnailImage: //example.com/image.jpg
---
作为后端工程师，有时候不可避免要跟前端打交道。
虽然在现代社会分工的趋势下， 前后端越来越独立， 但是在特定的领域里面比如 web视频播放， 网站开发中还是严重依赖前端 或者说浏览器。
本文通过介绍vue一窥前端开发。
<!--more-->


# Declarative rendering

Single-File Component(SFC) is a reusable self-contained block of code that encapsulates HTML, CSS and javascript that belong together, written inside a `.vue` file.


*Declarative rendering* using a template syntax that extends HTML.
Template be rendered based on JavaScript state, when state changes, the html updates automatically.
State that trigger updates when changed is considered reactive,
vue's reactive api:
* `.reactive()`     implemented use JavaScript Proxies 
* `.ref()`             take any value type and create an object that exposes the inner value under a `.value` property


## Template
mustaches are only used for text interpolation.
content inside template mustaches can be any valid JavaScript expression.



### Directive
A directive is a special attribute that starts with `v-` prefix. directive values are JS expressions that have access to the component's state

#### Attribute binding

To bind an attribute to a dynamic value, use `v-bind` directive
`v-bind` can be ignored.
```
<div [v-bind]:name="argument"></div>
```

#### Event listeners

listen to dom events using the `v-on` directive.
```
<button (v-on:|@)click="increment">{{ count }}</button>
```

#### Form bindings
`v-model` is a syntactic sugar using `v-bind` and `v-on` together.

#### conditional rending
`v-if` and `v-else` to create conditional rending.
```
<h1 v-if="awesome">Vue is awesome!</h1>
<h1 v-else>Oh no 😢</h1>
```

#### list rending
`v-for` for list rending


#### computed Property

use `computed()` to create a computed ref that computes its `.value` based on other reactive data sources.

### template Refs
use `ref="name"` to declare one ref in template


## Script

### reactive()     
implemented use JavaScript Proxies 
### ref()
take any value type and create an object that exposes the inner value under a `.value` property
### watch()
perform side effect reactively 
```
watch(state,func)
```



# lifeCycle Hooks
Each Vue component instances goes through a series of initialization steps when it's created.
For example:
set up data observation
compile the template 
mount the instance to the Dom
update dom when data changes
Life cycle hooks give users the opportunity to add their own code at specific stage.

`onMounted()` hook run after the component has finished the initial rendering and created the DOM nodes

`onUpdated()` run after the component has updated its DOM tree due to a reactive state change
`onBeforeUpdate()` run before the component is to update its DOM tree due to a reactive state change.

`onUnmounted()` run after the component has been unmounted

`onBeforeMount()` run before the component is to be mounted











