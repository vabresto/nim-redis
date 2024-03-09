import std/sequtils
import std/strformat
import std/strutils

{.experimental: "strictFuncs".}
{.experimental: "views".}


type
  RedisKind* = enum
    Null
    Error
    SimpleString
    BulkString
    Integer
    Array

  RedisValue* {.acyclic.} = object
    case kind*: RedisKind
    of Null:
      discard
    of Error:
      err*: string
    of SimpleString, BulkString:
      str*: string
    of Integer:
      num*: int64
    of Array:
      arr*: seq[RedisValue]


func `==`*(l, r: RedisValue): bool {.raises: [].} =
  if l.kind != r.kind:
    false
  else:
    case l.kind
    of Null:
      true
    of Error:
      l.err == r.err
    of SimpleString, BulkString:
      l.str == r.str
    of Integer:
      l.num == r.num
    of Array:
      l.arr == r.arr


when defined(redisGraphVerboseDollar):
  func `$`*(v: RedisValue): string {.raises: [].} =
    try:
      case v.kind
      of Null:
        "(RedisNull)"
      of Error:
        fmt"(RedisError '{v.err}')"
      of SimpleString:
        fmt"(RedisSimple '{v.str}')"
      of BulkString:
        fmt"(RedisString '{v.str}')"
      of Integer:
        fmt"(RedisInteger '{v.num}')"
      of Array:
        let inner = v.arr.map(`$`).join(", ")
        fmt"(RedisArray [{inner}])"
    except ValueError:
      "(RedisInvalid)"
else:
  func `$`*(v: RedisValue): string {.raises: [].} =
    try:
      case v.kind
      of Null:
        "null"
      of Error:
        fmt"ERR:'{v.err}'"
      of SimpleString:
        v.str
      of BulkString:
        v.str
      of Integer:
        $v.num
      of Array:
        let inner = v.arr.map(`$`).join(", ")
        fmt"[{inner}]"
    except ValueError:
      "ERR:RedisInvalid"

