# The performance comments below where using my Ubuntu linux desktop
# compiled with nim 0.10.3 sha1: 4b98768a and buildFlags:
# "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
import msg, msgarena, msgqueue, benchmark


# Having the warmup between 0 .. 0.25 seems to work best,
# at 133cy.  With a warmup of 1.0 the min was 147cy!
suite "bm msgareana", 0.25:
  var
    ma: MsgArenaPtr
    mq: MsgQueuePtr
    msg: MsgPtr
    tsa: array[0..4, TestStats]

  #No difference in timing consistently 133cy
  #discard newMsgArena()

  setup:
    ma = newMsgArena()
    mq = newMsgQueue("mq")
    msg = ma.getMsg(1, 0)
  teardown:
    mq.delMsgQueue()
    ma.delMsgArena()
    ma.retMsg(msg)

  test "test1", 1.0, tsa:
    mq.addTail(msg)
    msg = mq.rmvHead()
