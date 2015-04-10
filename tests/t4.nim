import msg, msgarena, msgqueue, msglooper, benchmark, os, locks

const
  runTime = 30.0
  threadCount = 3
  testStatsCount = 1

var
  ma: MsgArenaPtr
  ml1: MsgLooperPtr
  ml1RsvQ: QueuePtr

var
  ml1PmCount = 0
proc ml1Pm(msg: MsgPtr) =
  #echo "ml1Pm: **** msg=", msg
  ml1PmCount += 1
  msg.rspQ.addTail(msg)

ma = newMsgArena()
ml1 = newMsgLooper("ml1")
ml1RsvQ = newMsgQueue("ml1RsvQ", ml1.cond, ml1.lock)
ml1.addProcessMsg(ml1Pm, ml1RsvQ)

# include bmSuite so we can use it inside t(name: string)
include "bmsuite"

type
  TObj = object
    name: string
    index: int32

proc newTObj(name: string, index: int): TObj =
  result.name = name
  result.index = cast[int32](index and 0xFFFFFFFF)

proc t(tobj: TObj) {.thread.} =
  #echo "t+ tobj=", tobj

  bmSuite tobj.name, 1.0:
    echo suiteObj.suiteName & ".suiteObj=" & $suiteObj
    var
      msg: MsgPtr
      rspQ: QueuePtr
      tsa: array[0..testStatsCount-1, TestStats]

    setup:
      rspQ = newMsgQueue("rspQ-" & suiteObj.suiteName)
      msg = ma.getMsg(tobj.index, 0)
      msg.rspQ = rspQ

    teardown:
      ma.retMsg(msg)
      rspQ.delMsgQueue()

    test "ping-pong", runTime, tsa:
      ml1RsvQ.addTail(msg)
      msg = rspQ.rmvHead()

  #echo "t:- tobj=", tobj

var
  idx = 0
  threads: array[0..threadCount-1, TThread[TObj]]

for idx in 0..threads.len-1:
  var tobj = newTObj("X" & $idx, idx)
  createThread[TObj](threads[idx], t, tobj)

sleep(round(runTime * 1000.0 * 1.20))

echo "cleanup ml1PmCount=", ml1PmCount

ml1RsvQ.delMsgQueue()
ml1.delMsgLooper()
ma.delMsgArena()
