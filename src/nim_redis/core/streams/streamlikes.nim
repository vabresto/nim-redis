import std/asyncdispatch


type
  SimpleStreamLike* = concept ss
    ## SimpleStreamLike represents a minimal read/write stream concept.
    ## It should be matched by the stdlib FileStream and StringStream, as well as by this library's SocketStream.
    ss.readLine() is string
    ss.readStr(int) is string
    ss.write(string)
    ss.close()

  AsyncSimpleStreamLike* = concept ss
    ## AsyncSimpleStreamLike is the async analog of SimpleStreamLike.
    ## It is matched by AsyncSocketStream.
    ss.readLine() is Future[string]
    ss.readStr(int) is Future[string]
    ss.write(string) is Future[void]
    ss.close() ## not async


