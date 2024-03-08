import std/asyncdispatch
import std/strutils

import questionable/results as qr
import results

import nim_redis/core/redis_value
import nim_redis/core/streams/streamlikes

{.experimental: "strictFuncs".}
{.experimental: "views".}


proc readSimpleString(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync.} =
  let val = await s.readLine
  return success RedisValue(kind: SimpleString, str: val)


proc readError(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync.} =
  let val = await s.readLine
  return success RedisValue(kind: Error, err: val)


proc readInteger(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync.} =
  let str = await s.readLine
  without val =? str.parseBiggestInt.catch, error:
    return failure error
  return success RedisValue(kind: Integer, num: val)


proc readBulkString(s: SimpleStreamLike | AsyncSimpleStreamLike, size: int): Future[?!RedisValue] {.multisync.} =
  assert(size <= 512 * 1024 * 1024, "Redis Spec disallows bulk strings longer than 512 MB in length")
  if size < 0:
    # By spec, bulk string of length -1 should be interpreted as null
    if size == -1:
      return success RedisValue(kind: Null)
    else:
      return failure "Bulk string length was invalid: " & $size
  else:
    let str = await s.readStr(size)
    let lineEnd = await s.readStr(2)
    if lineEnd != "\r\n":
      return failure "Stream incorrectly terminated while reading bulk string"
    else:
      return success RedisValue(kind: BulkString, str: str)


proc readArray(s: SimpleStreamLike | AsyncSimpleStreamLike, size: int): Future[?!RedisValue] {.multisync.} =
  if size < 0:
    # By spec, bulk string of length -1 should be interpreted as null
    if size == -1:
      return success RedisValue(kind: Null)
    else:
      return failure "Bulk string length was invalid: " & $size
  else:
    var arr = newSeq[RedisValue]()
    for idx in 0 ..< size:
      let res = await s.readRedisValue
      without val =? res, error:
        return failure error
      arr.add val
    return success RedisValue(kind: Array, arr: arr)


proc readRedisValue*(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync.} =
  let instr = await s.readStr(1)
  case instr
  of "+":
    return await s.readSimpleString
  of "-":
    return await s.readError
  of ":":
    return await s.readInteger
  of "$":
    let res = await s.readInteger
    without size =? res, error:
      return failure error
    return await s.readBulkString(size.num.int)
  of "*":
    let res = await s.readInteger
    without size =? res, error:
      return failure error
    return await s.readArray(size.num.int)


