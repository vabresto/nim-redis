# Package

version       = "0.4.0"
author        = "Victor Brestoiu"
description   = "Nim Redis Client"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "chronicles#ab3ab545be0b550cca1c2529f7e97fbebf5eba81"
requires "nim >= 2.0.0"
requires "questionable#47692e0d923ada8f7f731275b2a87614c0150987"
requires "results#193d3c6648bd0f7e834d4ebd6a1e1d5f93998197"

# Indirect dependencies, pin git hashes because they don't properly update versions
requires "stew#1662762c0144854db60632e4115fe596ffa67fca"
