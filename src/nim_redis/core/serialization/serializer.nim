import std/sequtils
import std/strformat
import std/strutils

import nim_redis/core/redis_value

{.experimental: "strictFuncs".}
{.experimental: "views".}


func serialize*(r: RedisValue): string {.raises: [].} =
  try:
    case r.kind
    of Error:
      fmt"-{r.err}" & "\r\n"
    of Integer:
      fmt":{r.num}" & "\r\n"
    of SimpleString:
      fmt"+{r.str}" & "\r\n"
    of BulkString:
      fmt"${r.str.len}" & "\r\n" & r.str & "\r\n"
    of Null:
      "$-1\r\n"
    of Array:
      fmt"*{r.arr.len}" & "\r\n" & r.arr.map(serialize).join("")
  except ValueError:
    "-Failed to serialize input data!\r\n"

