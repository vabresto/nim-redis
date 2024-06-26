## Thread safety: Not explicitly guaranteed, but should be thread safe based on the system architecture.
## Redis itself is single threaded, the HTTP protocol guarantees message order, and Nim async *should* schedule
## things in the correct order. However, there could be something I'm missing.

import std/asyncdispatch
import std/asyncnet
import std/net
import std/options

import questionable/results as qr
import results

import nim_redis/core/redis_value
import nim_redis/core/serialization/parser
import nim_redis/core/serialization/parser2
import nim_redis/core/serialization/serializer
import nim_redis/core/streams/socketstreams

export redis_value

{.experimental: "strictFuncs".}
{.experimental: "views".}


type
  RedisClientBase[TStream] = ref object of RootObj
    stream: TSTream
    isClosed: bool = true

  RedisClient* = ref object of RedisClientBase[SocketStream]
    discard

  AsyncRedisClient* = ref object of RedisClientBase[AsyncSocketStream]
    discard


proc send*(r: RedisClient, args: varargs[string]): void =
  if args.len == 0:
    return
  var data = newSeq[RedisValue]()
  for s in args:
    data.add RedisValue(kind: BulkString, str: s)
  let val = RedisValue(kind: Array, arr: data)
  if r.isClosed:
    return
  r.stream.write(val.serialize)
  return


proc receive*(r: RedisClient): ?!RedisValue =
  if r.isClosed:
    return failure "Cannot receive from a closed client"
  return r.stream.readRedisValue()


proc cmd*(r: RedisClient, args: varargs[string]): ?!RedisValue =
  r.send(args)
  let res = ?r.receive()
  if res.kind == Error:
    return failure res.err
  return success res


proc cmd*(ar: AsyncRedisClient, args: seq[string]): Future[?!RedisValue] {.async.}=
  ## Note: Due to Nim limitation, the async version cannot capture varargs, so we have to use a seq instead
  ## https://github.com/nim-lang/Nim/issues/7831
  if args.len == 0:
    return failure "cmd must have at least one arg!"
  var data = newSeq[RedisValue]()
  for s in args:
    data.add RedisValue(kind: BulkString, str: s)
  let val = RedisValue(kind: Array, arr: data)
  await ar.stream.write(val.serialize)
  return await ar.stream.readRedisValue()


proc close*(c: RedisClient): void =
  # Tell the server we're closing
  if not c.isClosed:
    try:
      discard c.cmd("QUIT") # Probably don't want to discard
    finally:
      c.stream.close()
  c.isClosed = true


proc close*(c: AsyncRedisClient): Future[void] {.async.} =
  # Tell the server we're closing
  if not c.isClosed:
    try:
      discard await c.cmd(@["QUIT"])
    except Exception:
      discard
    finally:
      c.stream.close()
  c.isClosed = true


proc newRedisClient*(host: string,
                     port: Port = 6379.Port,
                     user: Option[string] = none string,
                     pass: Option[string] = none string): RedisClient =
  var socket = newSocket(buffered = true)
  socket.connect(host, port)
  let client = RedisClient(stream: newSocketStream(socket))
  client.isClosed = false
  var authCmd = @["AUTH"]
  if pass.isSome:
    if user.isSome:
      authCmd.add user.get
    authCmd.add pass.get
  # TODO: Somehow surface this maybe?
  discard client.cmd authCmd
  client


proc newAsyncRedisClient*(host: string,
                          port: Port = 6379.Port,
                          user: Option[string] = none string,
                          pass: Option[string] = none string): Future[AsyncRedisClient] {.async.} =
  var socket = newAsyncSocket(buffered = true)
  await socket.connect(host, port)
  let client = AsyncRedisClient(stream: newAsyncSocketStream(socket))
  client.isClosed = false
  var authCmd = @["AUTH"]
  if pass.isSome:
    if user.isSome:
      authCmd.add user.get
    authCmd.add pass.get
  # TODO: Somehow surface this maybe?
  discard await client.cmd authCmd
  return client


