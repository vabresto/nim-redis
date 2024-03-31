# Nim Redis

Nim has several Redis implementations already, why one more? The primary reason is to use `results` instead of
exceptions; this is most useful for writing async code, as exceptions currently bubble up annoyingly around
async boundaries. In particular, the `raises: []` pragma cannot be used on async functions because the async
transform itself can raise exceptions, and async stack traces are still quite messy.

## Install

Currently this package isn't published to nimble's registry, so it is recommended to install off of Github.
```bash
nimble install https://github.com/vabresto/nim-redis.git
```

You may wish to pin to a specific hash, for example:
```bash
nimble install https://github.com/vabresto/nim-redis.git#4af24e4e6eb42919b0fbe8105783841ae455b98e
```

## Features

- Sync and Async redis clients
- Pluggable architecture (can create a redis client with any stream type, including user-defined types)
- Full support for all redis commands (implements [RESP2](https://redis.io/docs/reference/protocol-spec/))
- Uses `results` instead of exceptions to indicate errors

## Examples

### Super simple

```nim
import nim_redis

let client = newRedisClient("localhost")

# Set key
discard client.cmd(@["SET", "hello", "world])

# Get key
let resp = client.cmd(@["GET", "hello"])
if resp.isOk:
  echo "Got: ", resp[]
else:
  echo "Error: ", resp.error.msg

client.close()
```

### Pubsub/Streams

See [pubsub.nim](tests/pubsub.nim) and [streams.nim](tests/streams.nim)


## License

MIT

## Contributing

Contributions are welcome! Please feel free to open a PR.
