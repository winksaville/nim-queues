import msg, msgarena, msgqueue, msglooper, benchmark, os, locks

var
  ma: MsgArenaPtr
  ml1: MsgLooperPtr
  ml1RsvQ: QueuePtr

var ml1PmCount = 0
proc ml1Pm(msg: MsgPtr) =
  #echo "ml1Pm: **** msg=", msg
  ml1PmCount += 1
  msg.rspQ.addTail(msg)

ma = newMsgArena()
ml1 = newMsgLooper("ml1")
ml1RsvQ = newMsgQueue("ml1RsvQ", ml1.cond, ml1.lock)
ml1.addProcessMsg(ml1Pm, ml1RsvQ)

suite "msglooper", 1.0:
  var
    msg: MsgPtr
    tsa: array[0..0, TestStats]
    rspQ1: QueuePtr

  setup:
    rspQ1 = newMsgQueue("rspQ1")
    msg = ma.getMsg(1, 0)
    msg.rspQ = rspQ1

  teardown:
    ma.retMsg(msg)
    rspQ1.delMsgQueue()

  test "test1", 10.0, tsa:
    ml1RsvQ.addTail(msg)
    msg = rspQ1.rmvHead()

echo "cleanup"

ml1RsvQ.delMsgQueue()
ml1.delMsgLooper()
ma.delMsgArena()
