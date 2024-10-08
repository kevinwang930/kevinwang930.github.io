---
title: "Mysql Service"
date: 2024-09-28T16:15:37+08:00
categories:
- database
- mysql
tags:
- mysql
keywords:
- mysql
#thumbnailImage: //example.com/image.jpg
---
This Article introduces Mysql `Service` structure
<!--more-->

## 2.4. Service

A `Service` is a struct of C function pointers
The server has all `service` structs defined and initialized so that the function pointers point to a actual `service` implementation functions



The big picture of plugin services


```plantuml


  actor "SQL client" as client
  box "MySQL Server" #LightBlue
    participant "Server Code" as server
    participant "Plugin" as plugin
  endbox

  == INSTALL PLUGIN ==
  server -> plugin : initialize
  activate plugin

  loop zero or many
    plugin -> server : service API call
    server --> plugin : service API result
  end
  plugin --> server : initialization done

  == CLIENT SESSION ==
  loop many
    client -> server : SQL command
    server -> server : Add reference for Plugin if absent
    loop one or many
      server -> plugin : plugin API call
      loop zero or many
        plugin -> server : service API call
        server --> plugin : service API result
      end
      plugin --> server : plugin API call result
    end
    server -> server : Optionally release reference for Plugin
    server --> client : SQL command reply
  end

  == UNINSTALL PLUGIN ==
  server -> plugin : deinitialize
  loop zero or many
    plugin -> server : service API call
    server --> plugin : service API result
  end
  plugin --> server : deinitialization done
  deactivate plugin

```
