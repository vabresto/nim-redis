import std/options
import std/os

import nim_redis

import nim_redis/core/redis_value
import nim_redis/core/serialization/parser
import nim_redis/core/serialization/serializer
import nim_redis/core/streams/socketstreams


proc rawSend(r: RedisClient, args: varargs[string]): void =
  if args.len == 0:
    return
  var data = newSeq[RedisValue]()
  for s in args:
    data.add RedisValue(kind: BulkString, str: s)
  let val = RedisValue(kind: Array, arr: data)
  r.stream.write(val.serialize)
  return

proc receive(r: RedisClient): ?!RedisValue =
  return r.stream.readRedisValue()

let client = newRedisClient("localhost", pass=some "foobarabc123")
let clientPtr = client.addr


proc receiveThreadProc() {.thread, gcsafe.} =
  while true:
    rawSend(clientPtr[], @["XREAD", "BLOCK", "0", "STREAMS", "race:france", "$"])
    let replyRaw = clientPtr[].receive()
    echo "Got raw reply"
    if replyRaw.isOk:
      echo "FINAL: ", replyRaw[]
    else:
      echo replyRaw.error.msg
      
    

var receiveThread: Thread[void]
createThread(receiveThread, receiveThreadProc)

# discard client.cmd(@["XREAD", "BLOCK", "0", "STREAMS", "race:france", "$"])

sleep(50_000)
client.close()
echo "Closing gracefully"
