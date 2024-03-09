import std/asyncdispatch
import std/net
import std/strutils

import questionable/results as qr
import results

import nim_redis/core/redis_value
import nim_redis/core/streams/streamlikes

import nim_redis/core/serialization/parser2

{.experimental: "strictFuncs".}
{.experimental: "views".}


proc readSimpleString(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync, gcsafe.} =
  let val = await s.readLine
  echo "[DBG] simplestring ", val
  return success RedisValue(kind: SimpleString, str: val)


proc readError(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync, gcsafe.} =
  let val = await s.readLine
  echo "[DBG] error ", val
  return success RedisValue(kind: Error, err: val)


proc readInteger(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync, gcsafe.} =
  let str = await s.readLine
  echo "[DBG] integer? ", str
  without val =? str.parseBiggestInt.catch, error:
    return failure error
  return success RedisValue(kind: Integer, num: val)


proc readBulkString(s: SimpleStreamLike, size: int): ?!RedisValue {.gcsafe, raises: [].} =
  try:
    assert(size <= 512 * 1024 * 1024, "Redis Spec disallows bulk strings longer than 512 MB in length")
    if size < 0:
      # By spec, bulk string of length -1 should be interpreted as null
      if size == -1:
        return success RedisValue(kind: Null)
      else:
        return failure "Bulk string length was invalid: " & $size
    else:
      try:
        let str = s.readStr(size)
        let lineEnd = s.readStr(2)
        if lineEnd != "\r\n":
          return failure "Stream incorrectly terminated while reading bulk string"
        else:
          return success RedisValue(kind: BulkString, str: str)
      except IOError:
        return failure "IOError: " & getCurrentExceptionMsg()
      except OSError:
        return failure "OSError: " & getCurrentExceptionMsg()
      except TimeoutError:
        return failure "TimeoutError: " & getCurrentExceptionMsg()
      except ValueError:
        return failure "ValueError: " & getCurrentExceptionMsg()
  except Exception:
    return failure "Unspecified Exception: " & getCurrentExceptionMsg()


proc readBulkString(s: AsyncSimpleStreamLike, size: int): Future[?!RedisValue] {.async, gcsafe.} =
  assert(size <= 512 * 1024 * 1024, "Redis Spec disallows bulk strings longer than 512 MB in length")
  if size < 0:
    # By spec, bulk string of length -1 should be interpreted as null
    if size == -1:
      return success RedisValue(kind: Null)
    else:
      return failure "Bulk string length was invalid: " & $size
  else:
    try:
      let str = await s.readStr(size)
      let lineEnd = await s.readStr(2)
      if lineEnd != "\r\n":
        return failure "Stream incorrectly terminated while reading bulk string"
      else:
        return success RedisValue(kind: BulkString, str: str)
    except IOError:
      return failure "IOError: " & getCurrentExceptionMsg()
    except OSError:
      return failure "OSError: " & getCurrentExceptionMsg()
    except TimeoutError:
      return failure "TimeoutError: " & getCurrentExceptionMsg()
    except ValueError:
      return failure "ValueError: " & getCurrentExceptionMsg()


proc readArray(s: SimpleStreamLike | AsyncSimpleStreamLike, size: int): Future[?!RedisValue] {.multisync, gcsafe.} =
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


proc readRedisValue*(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync, gcsafe.} =
  var buffer = ""

  let instr = when s is SimpleStreamLike:
    ?s.receiveRedisLeadingByte()
  else:
    await s.readStr(1)
  
  echo "[DBG] Got instr '", instr, "' len", instr.len
  case instr
  of "+":
    echo "[DBG] Calling simple string"
    when s is SimpleStreamLike:
      return s.readSimpleString2(buffer, RedisKind.SimpleString)
    else:
      return await s.readSimpleString
  of "-":
    when s is SimpleStreamLike:
      return s.readSimpleString2(buffer, RedisKind.Error)
    else:
      return await s.readError
  of ":":
    when s is SimpleStreamLike:
      return s.readSimpleString2(buffer, RedisKind.Integer)
    else:
      return await s.readInteger
  of "$":
    when s is SimpleStreamLike:
      let dataLen = ?s.readSimpleString2(buffer, RedisKind.Integer)
      let rawData = ?s.receiveRedisFixedLenData(dataLen.num)
      return success RedisValue(kind: BulkString, str: rawData)
    else:
      let res = await s.readInteger
      without size =? res, error:
        return failure error
      return await s.readBulkString(size.num.int)
  of "*":
    let res = await s.readInteger
    without size =? res, error:
      return failure error
    return await s.readArray(size.num.int)


