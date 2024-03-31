# 3rd party modules we re-export
import questionable/results as qr
import results

export qr
export results

# 1st party modules we export
import nim_redis/core/client
import nim_redis/core/redis_value

export client
export redis_value

## # Nim Redis
## 
## Create sync/async redis clients with `newRedisClient`/`newAsyncRedisClient`.
## 
## Send commands (and wait for responses) with `await client.cmd(@[ ... ])`, where the contents of the array are the
## raw strings to send to redis. The sync version supports variadic arguments (no need to use a list), but the async
## overload does not.
## 
## Alternatively, you can call `send` and `receive` manually if you prefer. This is primarily useful for implementing
## pubsub/stream handling.
## 
## Make sure you call `client.close()` when you're done with the client.
## 
