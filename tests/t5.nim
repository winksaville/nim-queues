# The performance comments below where using my Ubuntu linux desktop
# compiled with nim 0.10.3 sha1: 4b98768a and buildFlags:
# "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
#
# With just addTail/rmvHead and no getMsg/retMsg t1 is about
# 3x faster at 10cy compared to 30cy. Doing this made no
# difference using the extra newMsgArena warmupSeconds still
# made a difference.
import msg, msgarena, msgqueuewf, benchmark

# Having the warmup between 0 .. 0.25 seems to work best,
# at 10cy.  With a warmup of 1.0 the min was 24..33cy!
suite "bm msgareanawf", 0.25:
  var
    ma: MsgArenaPtr
    mq: MsgQueuePtr
    msg: MsgPtr
    tsa: array[0..4, TestStats]

  #No difference in timing consistently 10cy
  #discard newMsgArena()

  setup:
    ma = newMsgArena()
    mq = newMsgQueue("mq", ma.getMsg(0, 0))
    msg = ma.getMsg(1, 0)
  teardown:
    ma.retMsg(msg)
    mq.delMsgQueue()
    ma.delMsgArena()

  test "test1", 1.0, tsa:
    discard mq.addTail(msg)
    msg = mq.rmvHeadNonBlocking()
