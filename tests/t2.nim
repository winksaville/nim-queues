# Test msglooper
#
# This is ugly one, because the test loops once waiting
# a period of time. What about a benchmark in each looper?
# Or we use the cycle counter to measure each message pass
# individually or ....
#
# Also, we need a clean way to know when each looper is done.
# Right now I tell one looper to finish and use processingDone
# to signal the done condition. Actually processingDone needs
# to get signaled by each looper than then tell the master.
import msg, msgarena, msgqueue, msglooper, benchmark, os, locks


suite "msglooper", 0.25:
  var
    time = 2000
    ma: MsgArenaPtr

    ml1: MsgLooperPtr
    ml1q: MsgQueuePtr
    ml2: MsgLooperPtr
    ml2q: MsgQueuePtr
    msg: MsgPtr
    waitLock: TLock
    waitCond: TCond
    waiting: bool
    fired: bool
    #tsa: array[0..4, TestStats]
    ts: TestStats

  waitLock.initLock()
  waitCond.initCond()

  proc processingDone =
    waitLock.acquire()
    block:
      fired = true
      if waiting:
        echo "processingDone: signal"
        waitCond.signal()
      else:
        echo "processingDone: not waiting"
    waitLock.release()

  var ml1PmCount = 0
  proc ml1Pm(msg: MsgPtr) =
    #echo "ml1Pm: **** msg=", msg
    ml1PmCount += 1
    ml2q.addTail(msg)

  var ml2PmCount = 0
  proc ml2Pm(msg: MsgPtr) =
    #echo "ml2Pm: **** msg=", msg
    ml2PmCount += 1
    if msg.cmd != 0:
      ml1q.addTail(msg)
    else:
      echo "ml2Pm: done"
      ma.retMsg(msg)
      processingDone()

  setup:
    ma = newMsgArena()

    ml1 = newMsgLooper("ml1")
    ml1q = newMsgQueue("ml1q", ml1.cond, ml1.lock)
    ml1.addProcessMsg(ml1Pm, ml1q)
    ml2 = newMsgLooper("ml2")
    ml2q = newMsgQueue("ml2q", ml2.cond, ml2.lock)
    ml2.addProcessMsg(ml2Pm, ml2q)

  teardown:
    # TODO: implement "join" so we no both loopers are done
    sleep(100)
    ml1.delMsgLooper()
    ml2.delMsgLooper()
    ma.delMsgArena()
    var msgCount = ml1PmCount + ml2PmCount
    var timeInSecs = float(time) / 1000.0
    echo "ml1PmCount:" & $ml1PmCount & " + " & "ml2PmCount:" & $ml2PmCount & " = " & $msgCount
    echo "rate=" & $(float(msgCount) / timeInSecs) & "msgs/sec"
    echo "time=" & $(timeInSecs / float(msgCount)) & "sec/msg"

  test "test1", 1, ts:
    # Start message passing
    msg = ma.getMsg(1, 0)
    fired = false
    ml1q.addTail(msg)

    # wait for a period of time
    echo suiteObj.fullName & ": sleeping"
    sleep(time)

    # Send the zero message to stop the passing
    msg = ma.getMsg(0, 0)
    ml2q.addTail(msg)

    # Wait til done
    waitLock.acquire()
    block:
      if not fired:
        waiting = true
        echo suiteObj.fullName & ": waiting"
        waitCond.wait(waitLock)
        echo suiteObj.fullName & ": ready"
      else:
        echo suiteObj.fullName & ": fired not waiting"
    waitLock.release()
