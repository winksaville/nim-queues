# The performance comments below where using my Ubuntu linux desktop
# compiled with nim 0.10.3 sha1: 4b98768a and buildFlags:
# "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
#
# With just addTail/rmvHead and no getMsg/retMsg t1 is
# 82cy instead of 133cy somewhat faster but much slower
# the what I had the broken non-intrusive code at which
# was 10cy. It will be interesting to see if doing it
# correctly what its speed will be, be much closer to
# the 10cy rather than the 82cy as it should be just one
# pointer copy longer than my broken code. Of course
# that is ignoring allocating messages will be slower
# but if they are effectively cached this should be a
# problem. We'll see
import msg, msgarena, msgqueueiwf, benchmark

var
  ma: MsgArenaPtr
  mq: MsgQueuePtr
  tsa: array[0..4, TestStats]
  ts: TestStats

proc addMsgs(loops: int32, baseCmd: int32, isFirstEmpty: bool) =
  for i in baseCmd..baseCmd+loops-1:
    var msg = ma.getMsg(cast[int32](i), 0)
    var isAddedToEmpty = mq.addTail(msg)
    if i == baseCmd:
      if isFirstEmpty != isAddedToEmpty:
        echo "Error: isFirstEmpty:" & $isFirstEmpty & " != " & "isAddedToEmpty:" & $isAddedToEmpty &
          " msg=" & $msg & " mq=" & $mq
    elif isAddedToEmpty:
      echo "Error: addTail reported empty and shouldn't: msg=" & $msg & " mq=" & $mq &
        " i=" & $i & " loops=" & $loops & " baseCmd=" & $baseCmd

proc rmvMsgs(loops: int32, baseCmd: int32) =
  for i in baseCmd..baseCmd+loops-1:
    var msg = mq.rmvHeadNonBlocking()
    if msg.cmd != i:
      echo "Error: msg.cmd:" & $msg.cmd & " != " & "i:" & $i
    ma.retMsg(msg)

proc chkEmpty() =
  var msg = mq.rmvHeadNonBlocking()
  if msg != nil:
    echo "Error: msg != nil msg=" & $msg

proc testAddThenRmv(loops: int32) =
  addMsgs(loops, 0, true)
  rmvMsgs(loops, 0)
  chkEmpty()

suite "bm msgareanawf", 0.25:

  var
    msg: MsgPtr

  setup:
    ma = newMsgArena()
    mq = newMsgQueue("mq", ma.getMsg(-1, 0))
    msg = ma.getMsg(1, 0)
  teardown:
    ma.retMsg(msg)
    mq.delMsgQueue()
    ma.delMsgArena()

  test "test add/rmv perf", 1.0, tsa:
    discard mq.addTail(msg)
    msg = mq.rmvHeadNonBlocking()

  setup:
    ma = newMsgArena()
    mq = newMsgQueue("mq", ma.getMsg(-1, 0))
  teardown:
    mq.delMsgQueue()
    ma.delMsgArena()

  test "test add/rmv 0", 1, ts:
    testAddThenRmv(0)

  test "test add/rmv 1", 1, ts:
    testAddThenRmv(1)

  test "test add/rmv 2", 1, ts:
    testAddThenRmv(2)

  test "test add/rmv 3", 1, ts:
    testAddThenRmv(3)

  test "test add/rmv X", 1, ts:
    addMsgs(2, 0, true)
    rmvMsgs(1, 0)
    addMsgs(1, 2, false)
    rmvMsgs(2, 1)
    chkEmpty()
