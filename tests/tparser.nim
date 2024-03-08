import std/streams
import std/unittest

import questionable/results

import nim_redis/core/redis_value
import nim_redis/core/serialization/parser {.all.}


suite "parser trivial":
  test "simple string ok":
    var s = newStringStream("OK\r\n")
    let val = s.readSimpleString.tryGet()
    check val.kind == SimpleString
    check val.str == "OK"

  test "bulk string ok":
    var s = newStringStream("hello\r\n")
    let val = s.readBulkString(5).tryGet()
    check val.kind == BulkString
    check val.str == "hello"

  test "error ok":
    var s = newStringStream("Error message\r\n")
    let val = s.readError.tryGet()
    check val.kind == Error
    check val.err == "Error message"

  test "integer ok":
    var s = newStringStream("1000\r\n")
    let val = s.readInteger.tryGet()
    check val.kind == Integer
    check val.num == 1_000


suite "parser full":
  test "simple string 'ok'":
    var s = newStringStream("+OK\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == SimpleString
    check val.str == "OK"

  test "error 'Error message'":
    var s = newStringStream("-Error message\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Error
    check val.err == "Error message"
    check s.atEnd

  test "error 'ERR'":
    var s = newStringStream("-ERR unknown command 'helloworld'\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Error
    check val.err == "ERR unknown command 'helloworld'"
    check s.atEnd

  test "error 'WRONGTYPE'":
    var s = newStringStream("-WRONGTYPE Operation against a key holding the wrong kind of value\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Error
    check val.err == "WRONGTYPE Operation against a key holding the wrong kind of value"
    check s.atEnd

  test "int 0":
    var s = newStringStream(":0\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Integer
    check val.num == 0
    check s.atEnd

  test "int 1,000":
    var s = newStringStream(":1000\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Integer
    check val.num == 1_000
    check s.atEnd

  test "bulk string 'hello'":
    var s = newStringStream("$5\r\nhello\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == BulkString
    check val.str == "hello"
    check s.atEnd

  test "bulk string empty string":
    var s = newStringStream("$0\r\n\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == BulkString
    check val.str == ""
    check s.atEnd

  test "bulk string null":
    var s = newStringStream("$-1\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Null
    check s.atEnd

  test "array null":
    var s = newStringStream("*-1\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Null
    check s.atEnd

  test "array empty":
    var s = newStringStream("*0\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Array
    check val.arr == newSeq[RedisValue]()
    check s.atEnd

  test "array hello world":
    var s = newStringStream("*2\r\n$5\r\nhello\r\n$5\r\nworld\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Array
    check val.arr == @[
      RedisValue(kind: BulkString, str: "hello"),
      RedisValue(kind: BulkString, str: "world"),
    ]
    check s.atEnd

  test "array 1, 2, 3":
    var s = newStringStream("*3\r\n:1\r\n:2\r\n:3\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Array
    check val.arr == @[
      RedisValue(kind: Integer, num: 1),
      RedisValue(kind: Integer, num: 2),
      RedisValue(kind: Integer, num: 3),
    ]
    check s.atEnd

  test "array mixed":
    var s = newStringStream("*5\r\n:1\r\n:2\r\n:3\r\n:4\r\n$5\r\nhello\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Array
    check val.arr == @[
      RedisValue(kind: Integer, num: 1),
      RedisValue(kind: Integer, num: 2),
      RedisValue(kind: Integer, num: 3),
      RedisValue(kind: Integer, num: 4),
      RedisValue(kind: BulkString, str: "hello"),
    ]
    check s.atEnd

  test "array containing null":
    var s = newStringStream("*3\r\n$5\r\nhello\r\n$-1\r\n$5\r\nworld\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Array
    check val.arr == @[
      RedisValue(kind: BulkString, str: "hello"),
      RedisValue(kind: Null),
      RedisValue(kind: BulkString, str: "world"),
    ]
    check s.atEnd

  test "array nested":
    var s = newStringStream("*2\r\n*3\r\n:1\r\n:2\r\n:3\r\n*2\r\n+Hello\r\n-World\r\n")
    let val = s.readRedisValue.tryGet()
    check val.kind == Array
    check val.arr == @[
      RedisValue(kind: Array, arr: @[
        RedisValue(kind: Integer, num: 1),
        RedisValue(kind: Integer, num: 2),
        RedisValue(kind: Integer, num: 3),
      ]),
      RedisValue(kind: Array, arr: @[
        RedisValue(kind: SimpleString, str: "Hello"),
        RedisValue(kind: Error, err: "World"),
      ]),
    ]
    check s.atEnd


