# The performance comments below where using my Ubuntu linux desktop
# compiled with nim 0.10.3 sha1: 4b98768a and buildFlags:
# "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
import msg, msgarena, msgqueue, benchmark


# Having the warmup between 0 .. 0.25 seems to work best.
# With a warmup of 1.0 the min was 258cy!
suite "bm msgareana", 0.25:
  var
    ma: MsgArenaPtr
    mq: MsgQueuePtr
    msg: MsgPtr
    tsa: array[0..4, TestStats]

  # For some reason doing this newMsgArena gives
  # more consistent results. A minimum of 244cy
  # and "good minC" at 253cy very consistently
  # when running tests/t1. Not doing this I see
  # min's of 259..262cy and 277cy with a "good
  # minC". This maybe related to the fact that
  # newMsgArena warms up the caches better as
  # it does some allocShared0 call
  discard newMsgArena()

  setup:
    ma = newMsgArena()
    mq = newMsgQueue("mq")
  teardown:
    mq.delMsgQueue()
    ma.delMsgArena()

  test "test1", 1.0, tsa:
    msg = ma.getMsg(1, 0)
    mq.addTail(msg)
    msg = mq.rmvHead()
    ma.retMsg(msg)
