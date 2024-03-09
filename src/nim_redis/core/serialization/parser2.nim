import std/net
import std/streams
import std/strutils

import questionable/results as qr
import results

import nim_redis/core/redis_value
import nim_redis/core/streams/streamlikes
import nim_redis/core/streams/socketstreams

{.experimental: "strictFuncs".}
{.experimental: "views".}


proc receiveRedisLeadingByte*(s: SocketStream): ?!string {.gcsafe, raises: [].} =
  var loops = 0
  var buffer: string
  buffer.setLen(1)
  while true:
    inc loops
    if loops > 500:
      return failure "Timed out"
    try:
      let bytesRead = recv(s.socket, buffer[0].addr, 1, 15)

      if bytesRead > 0:
        echo "[DBG2] receiveRedisLeadingByte bytesRead ", bytesRead, ": ", buffer
        return success buffer
    except TimeoutError:
      discard
    except OSError:
      echo "E FAIL OS", getCurrentExceptionMsg()
      return failure "OS Error"
  return failure "End of control flow in receiveRedisLeadingByte"


proc receiveRedisLine(s: SocketStream, buffer: var string): ?!string {.gcsafe, raises: [].} =
  var totalBytesRead = 0
  var bufferPos = 0
  var loops = 0
  while true:
    inc loops
    if loops > 500:
      return failure "Timed out"
    try:
      if bufferPos + 1 >= buffer.len:
        if buffer.len == 0:
          buffer.setLen(32)
        else:
          buffer.setLen(buffer.len * 2)

      let bytesRead = recv(s.socket, buffer[bufferPos].addr, 1, 5)

      if bytesRead > 0:
        totalBytesRead += bytesRead
        bufferPos += bytesRead

        if bufferPos > 2 and buffer[bufferPos - 2] == '\r' and buffer[bufferPos - 1] == '\n':
          break
    except TimeoutError:
      discard
    except OSError:
      echo "E FAIL OS"
      return failure "OS Error"

  echo "[DBG2] read bytes: ", totalBytesRead, ": ", buffer
  let val = buffer[0 .. totalBytesRead - 2 - 1]
  return success val


proc receiveRedisFixedLenData*(s: SocketStream, dataLen: int): ?!string {.gcsafe, raises: [].} =
  # This parses just the fixed len data portion
  # So for `$5\r\nhello\r\n`, this processes `hello\r\n`
  var totalBytesRead = 0
  var bufferPos = 0
  var loops = 0
  var buffer: string
  buffer.setLen(dataLen + 2)
  while true:
    inc loops
    if loops > 500:
      return failure "Timed out"
    try:
      if bufferPos + 1 >= buffer.len:
        if buffer.len == 0:
          buffer.setLen(32)
        else:
          buffer.setLen(buffer.len * 2)

      let bytesRead = recv(s.socket, buffer[bufferPos].addr, 1, 5)

      if bytesRead > 0:
        totalBytesRead += bytesRead
        bufferPos += bytesRead

        if totalBytesRead >= dataLen and bufferPos > 2 and buffer[bufferPos - 2] == '\r' and buffer[bufferPos - 1] == '\n':
          break
    except TimeoutError:
      discard
    except OSError:
      echo "E FAIL OS"
      return failure "OS Error"

  echo "[DBG2] read bytes: ", totalBytesRead, ": ", buffer
  let val = buffer[0 .. totalBytesRead - 2 - 1]
  return success val


proc readSimpleString2*(s: SocketStream, buffer: var string, resultKind: RedisKind): ?!RedisValue {.gcsafe, raises: [].} =
  # At this point, we've already parsed the leading `+` and just need to continue reading data until we get \r\n
  # However, note that the buffer may already have data, so we only want to return after bufferPos, and then update the value

  if resultKind != RedisKind.SimpleString and resultKind != RedisKind.Error and resultKind != RedisKind.Integer:
    return failure "Invalid call to readSimpleString2; result kind must be either SimpleString or Error or Integer"

  let val = ?receiveRedisLine(s, buffer)

  if resultKind == SimpleString:
    return success RedisValue(kind: SimpleString, str: val)
  elif resultKind == Integer:
    try:
      return success RedisValue(kind: Integer, num: val.parseBiggestInt)
    except ValueError:
      return failure "Failed to parse as integer: " & val
  else:
    return success RedisValue(kind: Error, err: val)
