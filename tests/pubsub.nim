## NOTE: Not a unit test because it requires a redis instance to interact with, this is more of an example.

import std/options
import std/os

import nim_redis

import nim_redis/core/redis_value
import nim_redis/core/serialization/parser
import nim_redis/core/serialization/serializer
import nim_redis/core/streams/socketstreams


proc receive(r: RedisClient): ?!RedisValue =
  return r.stream.readRedisValue

let client = newRedisClient("localhost", pass=some "foobarabc123")
let clientPtr = client.addr


proc receiveThreadProc() {.thread, gcsafe.} =
  while true:
    let replyRaw = clientPtr[].receive()
    if replyRaw.isOk:
      echo "FINAL: ", replyRaw[]
    

var receiveThread: Thread[void]
createThread(receiveThread, receiveThreadProc)

discard client.cmd(@["SUBSCRIBE", "chan"])

sleep(100_000)
client.close()
