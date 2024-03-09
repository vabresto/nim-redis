import std/asyncdispatch
import std/net
import std/strutils

import chronicles
import questionable/results as qr
import results

import nim_redis/core/redis_value
import nim_redis/core/streams/streamlikes

import nim_redis/core/serialization/parser2
import nim_redis/core/streams/socketstreams

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
      echo "[DBG] Calling array[", idx, "]"
      let res = await s.readRedisValue()
      without val =? res, error:
        return failure error
      arr.add val
    echo "Done reading array", arr
    return success RedisValue(kind: Array, arr: arr)


proc readRedisValue*(s: SimpleStreamLike | AsyncSimpleStreamLike): Future[?!RedisValue] {.multisync, gcsafe.} =
  var buffer = ""

  let instr: string = when s is SocketStream:
    ?(s.receiveRedisLeadingByte())
  else:
    await s.readStr(1)
  
  echo "Got instr '", instr, "', len: ", instr.len
  case instr
  of "+":
    echo "[DBG] Calling simple string ..."
    when s is SocketStream:
      let res = s.readSimpleString2(buffer, RedisKind.SimpleString)
      echo "[DBG] Done calling simple string"
      return res
    else:
      return await s.readSimpleString
  of "-":
    echo "[DBG] Calling err"
    when s is SocketStream:
      let res = s.readSimpleString2(buffer, RedisKind.Error)
      echo "[DBG] Done calling err"
      return res
    else:
      return await s.readError
  of ":":
    echo "[DBG] Calling integer"
    when s is SocketStream:
      let res = s.readSimpleString2(buffer, RedisKind.Integer)
      echo "[DBG] Done calling integer"
      return res
    else:
      return await s.readInteger
  of "$":
    echo "[DBG] Calling bulk string"
    when s is SocketStream:
      let dataLen = ?s.readSimpleString2(buffer, RedisKind.Integer)
      echo "[DBG] Done calling bulk string: data len"
      let rawData = ?s.receiveRedisFixedLenData(dataLen.num)
      let res = success RedisValue(kind: BulkString, str: rawData)
      echo "[DBG] Done calling bulk string"
      return res
    else:
      let res = await s.readInteger
      without size =? res, error:
        return failure error
      return await s.readBulkString(size.num.int)
  of "*":
    echo "[DBG] Calling array"
    let res = when s is SocketStream:
      block:
        let res = s.readSimpleString2(buffer, RedisKind.Integer)
        echo "[DBG] Done calling array: integer"
        res
    else:
      await s.readInteger
    without size =? res, error:
      return failure error
    let finalRes = await s.readArray(size.num.int)
    echo "[DBG] Done calling array"
    return finalRes


