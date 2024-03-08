mport std/streams
import std/unittest

import questionable/results

import nim_redis/core/redis_value
import nim_redis/core/serialization/parser
import nim_redis/core/serialization/serializer


suite "serializer trivial":
  test "simple string ok":
    let init = RedisValue(kind: SimpleString, str: "OK")
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "bulk string ok":
    let init = RedisValue(kind: BulkString, str: "hello")
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "error ok":
    let init = RedisValue(kind: Error, err: "Error message")
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "integer ok":
    let init = RedisValue(kind: Integer, num: 1_000)
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init


suite "serializer full":
  test "error 'ERR'":
    let init = RedisValue(kind: Error, err: "ERR unknown command 'helloworld'")
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "error 'WRONGTYPE'":
    let init = RedisValue(kind: Error, err: "WRONGTYPE Operation against a key holding the wrong kind of value")
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "int 0":
    let init = RedisValue(kind: Integer, num: 0)
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "int -1,000":
    let init = RedisValue(kind: Integer, num: -1_000)
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "bulk string empty string":
    let init = RedisValue(kind: BulkString, str: "")
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "bulk string special chars":
    let init = RedisValue(kind: BulkString, str: "a\r\nb\r\nc\n\r")
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "null":
    let init = RedisValue(kind: Null)
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "array empty":
    let init = RedisValue(kind: Array, arr: @[])
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "array hello world":
    let init = RedisValue(kind: Array, arr: @[
      RedisValue(kind: BulkString, str: "hello"),
      RedisValue(kind: BulkString, str: "world"),
    ])
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "array 1, 2, 3":
    let init = RedisValue(kind: Array, arr: @[
      RedisValue(kind: Integer, num: 1),
      RedisValue(kind: Integer, num: 2),
      RedisValue(kind: Integer, num: 3),
    ])
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "array mixed":
    let init = RedisValue(kind: Array, arr: @[
      RedisValue(kind: Integer, num: 1),
      RedisValue(kind: Integer, num: 2),
      RedisValue(kind: Integer, num: 3),
      RedisValue(kind: Integer, num: 4),
      RedisValue(kind: BulkString, str: "hello"),
    ])
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "array containing null":
    let init = RedisValue(kind: Array, arr: @[
      RedisValue(kind: BulkString, str: "hello"),
      RedisValue(kind: Null),
      RedisValue(kind: BulkString, str: "world"),
    ])
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init

  test "array nested":
    let init = RedisValue(kind: Array, arr: @[
      RedisValue(kind: Array, arr: @[
        RedisValue(kind: Integer, num: 1),
        RedisValue(kind: Integer, num: 2),
        RedisValue(kind: Integer, num: 3),
      ]),
      RedisValue(kind: Array, arr: @[
        RedisValue(kind: SimpleString, str: "Hello"),
        RedisValue(kind: Error, err: "World"),
      ]),
    ])
    var s = newStringStream(init.serialize)
    let val = s.readRedisValue.tryGet
    check val == init


