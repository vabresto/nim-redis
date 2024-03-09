import std/net
import std/strutils

import chronicles
import questionable/results as qr
import results

import nim_redis/core/redis_value
import nim_redis/core/streams/socketstreams

{.experimental: "strictFuncs".}
{.experimental: "views".}

const
  kSocketTimeoutSmall = 5
  kSocketTimeoutBig = 15


proc receiveRedisLeadingByte*(s: SocketStream): ?!string {.gcsafe, raises: [].} =
  var loops = 0
  var buffer: string
  buffer.setLen(1)
  while true:
    inc loops
    if loops > 500:
      # info "receiveRedisLeadingByte timed out", loops, kSocketTimeoutBig
      return failure "Timed out"
    try:
      let bytesRead = recv(s.socket, buffer[0].addr, 1, kSocketTimeoutBig)

      if bytesRead > 0:
        # debug "receiveRedisLeadingByte bytesRead", bytesRead
        return success buffer
    except TimeoutError:
      discard
    except OSError:
      error "receiveRedisLeadingByte got OS error", msg=getCurrentExceptionMsg()
      return failure "OS Error"
  error "receiveRedisLeadingByte got to end of control flow!"
  return failure "End of control flow in receiveRedisLeadingByte"


proc receiveRedisLine(s: SocketStream, buffer: var string): ?!string {.gcsafe, raises: [].} =
  var totalBytesRead = 0
  var bufferPos = 0
  var loops = 0
  while true:
    inc loops
    if loops > 500:
      warn "receiveRedisLine timed out", loops, kSocketTimeoutSmall
      return failure "Timed out"
    try:
      if bufferPos + 1 >= buffer.len:
        if buffer.len == 0:
          buffer.setLen(32)
        else:
          buffer.setLen(buffer.len * 2)

      let bytesRead = recv(s.socket, buffer[bufferPos].addr, 1, kSocketTimeoutSmall)

      if bytesRead > 0:
        totalBytesRead += bytesRead
        bufferPos += bytesRead

        if bufferPos > 2 and buffer[bufferPos - 2] == '\r' and buffer[bufferPos - 1] == '\n':
          break
    except TimeoutError:
      discard
    except OSError:
      error "receiveRedisLine got OS error", msg=getCurrentExceptionMsg()
      return failure "OS Error"

  # debug "receiveRedisLine read bytes", totalBytesRead, buffer
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
      warn "receiveRedisFixedLenData timed out", loops, kSocketTimeoutSmall
      return failure "Timed out"
    try:
      if bufferPos + 1 >= buffer.len:
        if buffer.len == 0:
          buffer.setLen(8)
        else:
          buffer.setLen(buffer.len * 2)

      let bytesRead = recv(s.socket, buffer[bufferPos].addr, 1, kSocketTimeoutSmall)

      if bytesRead > 0:
        totalBytesRead += bytesRead
        bufferPos += bytesRead

        let chk1 = totalBytesRead >= dataLen
        let chk2 = bufferPos > 2
        let chk3 = chk2 and buffer[bufferPos - 2] == '\r'
        let chk4 = chk2 and buffer[bufferPos - 1] == '\n'

        # info "receiveRedisFixedLenData status", dataLen, totalBytesRead, chk1, chk2, chk3, chk4

        if chk1 and chk2 and chk3 and chk4:
          break
    except TimeoutError:
      discard
    except OSError:
      error "receiveRedisFixedLenData got OS error", msg=getCurrentExceptionMsg()
      return failure "OS Error"

  # debug "receiveRedisFixedLenData read bytes", totalBytesRead, buffer
  let val = buffer[0 .. totalBytesRead - 2 - 1]
  return success val


proc readSimpleString2*(s: SocketStream, buffer: var string, resultKind: RedisKind): ?!RedisValue {.gcsafe, raises: [].} =
  # At this point, we've already parsed the leading `+` and just need to continue reading data until we get \r\n
  # However, note that the buffer may already have data, so we only want to return after bufferPos, and then update the value

  if resultKind != RedisKind.SimpleString and resultKind != RedisKind.Error and resultKind != RedisKind.Integer:
    error "Invalid call to readSimpleString2; result kind must be either SimpleString or Error or Integer", resultKind
    return failure "Invalid call to readSimpleString2; result kind must be either SimpleString or Error or Integer"

  let val = ?receiveRedisLine(s, buffer)

  if resultKind == SimpleString:
    return success RedisValue(kind: SimpleString, str: val)
  elif resultKind == Integer:
    try:
      return success RedisValue(kind: Integer, num: val.parseBiggestInt)
    except ValueError:
      error "Failed to parse as integer", val
      return failure "Failed to parse as integer: " & val
  else:
    return success RedisValue(kind: Error, err: val)
