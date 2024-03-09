## Implement stream interface using sync and async sockets

import std/asyncdispatch
import std/asyncnet
import std/net


type
  SocketStreamBase[TSocket] = ref object of RootObj
    socket*: TSocket

  SocketStream* = ref object of SocketStreamBase[net.Socket]
    timeoutMs*: int

  AsyncSocketStream* = ref object of SocketStreamBase[asyncnet.AsyncSocket]
    discard


proc close*(ss: sink SocketStream | AsyncSocketStream) =
  ## Closes the underlying socket and releases any other resources. The client should not be used again.
  ## **See also:**
  ## * Sync: https://nim-lang.org/docs/net.html#close%2CSocket
  ## * Async: https://nim-lang.org/docs/asyncnet.html#close%2CAsyncSocket
  ss.socket.close()


# Note: The following two functions are commented out because they are unused. Instead of removing them, it makes
# sense to leave commented out here in case someone needs/refers to them, so they don't have to be reimplemented. Would
# be somewhat of a discussion as to whether or not they should also be referred to in the concept.

# proc readChar*(ss: SocketStream | AsyncSocketStream, length: int): Future[char] {.multisync.} =
#   ## Attempt to read a char from the stream. Sync socket supports a timeout by setting it on the object.
#   ## Returns null term '\0' if it fails to read data. Buffered and unbuffered sockets have the same behaviour as
#   ## the underlying Nim standard library sockets.
#   ## **See also:**
#   ## * Sync: https://nim-lang.org/docs/net.html#recv%2CSocket%2Cpointer%2Cint%2Cint
#   ## * Async: https://nim-lang.org/docs/asyncnet.html#recv%2CAsyncSocket%2Cint
#   var res: string

#   when ss is SocketStream:
#     let timeout = ss.timeoutMs
#     discard recv(ss.socket, res, 1, timeout)
#   else:
#     res = await recv(ss.socket, 1)

#   if res.len == 1:
#     return res[0]
#   else:
#     return '\0'


proc readData*(ss: SocketStream | AsyncSocketStream, buffer: pointer, bufLen: int): Future[int] {.multisync.} =
  ## Attempt to fill a buffer from the stream. Sync socket supports a timeout by setting it on the object.
  ## Buffered and unbuffered sockets have the same behaviour as the underlying Nim standard library sockets.
  ## **See also:**
  ## * Sync: https://nim-lang.org/docs/net.html#recv%2CSocket%2Cpointer%2Cint%2Cint
  ## * Async: https://nim-lang.org/docs/asyncnet.html#recvInto%2CAsyncSocket%2Cpointer%2Cint
  when ss is SocketStream:
    return recv(ss.socket, buffer, bufLen, 15)
  else:
    return await recvInto(ss.socket, buffer, bufLen)


proc readLine*(ss: SocketStream | AsyncSocketStream): Future[string] {.multisync.} =
  ## Attempt to read a line from the stream. Sync socket supports a timeout by setting it on the object.
  ## Uses the behaviour of the Nim standard library sockets; notably that means that `\r\L` is stripped from the result,
  ## unless that is the entire result. See the standard library documentation for more details:
  ## **See also:**
  ## * Sync: https://nim-lang.org/docs/net.html#recvLine%2CSocket%2Cint
  ## * Async: https://nim-lang.org/docs/asyncnet.html#recvLine%2CAsyncSocket
  when ss is SocketStream:
    return recvLine(ss.socket, ss.timeoutMs)
  else:
    return await recvLine(ss.socket)


proc readStr*(ss: SocketStream | AsyncSocketStream, length: int): Future[string] {.multisync.} =
  ## Attempt to read a number of bytes from the stream. Sync socket supports a timeout by setting it on the object.
  ## Uses the behaviour of the Nim standard library sockets.
  ## See the standard library documentation for more details:
  ## **See also:**
  ## * Sync: https://nim-lang.org/docs/net.html#recv%2CSocket%2Cstring%2Cint%2Cint
  ## * Async: https://nim-lang.org/docs/asyncnet.html#recv%2CAsyncSocket%2Cint
  when ss is SocketStream:
    var res: string
    let readAmt = recv(ss.socket, res, length, ss.timeoutMs)
    if readAmt != length:
      raise newException(ValueError, "Failed to read requested amount!")
    return res
  else:
    return await recv(ss.socket, length)


proc write*(ss: SocketStream | AsyncSocketStream, data: string): Future[void] {.multisync.} =
  ## Send data down the socket.
  ## **See also:**
  ## * Sync: https://nim-lang.org/docs/net.html#recv%2CSocket%2Cstring%2Cint%2Cint
  ## * Async: https://nim-lang.org/docs/asyncnet.html#recv%2CAsyncSocket%2Cint
  when ss is SocketStream:
    send(ss.socket, data)
  else:
    return send(ss.socket, data)


proc newSocketStream*(socket: sink net.Socket, timeoutMs: int = -1): SocketStream =
  ## Create a new sync socket stream.
  ## Note: The socket must be connected before attaching it to the stream. The stream takes ownership upon creation.
  SocketStream(socket: socket, timeoutMs: timeoutMs)


proc newAsyncSocketStream*(socket: sink AsyncSocket): AsyncSocketStream =
  ## Create a new async socket stream.
  ## Note: The socket must be connected before attaching it to the stream. The stream takes ownership upon creation.
  AsyncSocketStream(socket: socket)


