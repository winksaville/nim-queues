import os, locks
import msg, msgqueue, msgarena

#when not defined(release):
#  const DBG = true
#else:
#  const DBG = false

const
  DBG = false
  listMsgProcessorMaxLen = 10

type
  ProcessMsg* = proc(msg: MsgPtr)

  MsgProcessorPtr* = ptr MsgProcessor
  MsgProcessor* = object
    mq: MsgQueuePtr
    pm: ProcessMsg

  MsgLooperPtr* = ptr MsgLooper

  MsgLooper* = object
    name: string
    initialized: bool
    done: bool
    cond*: ptr TCond
    lock*: ptr TLock
    listMsgProcessorLen: int
    listMsgProcessor: ptr array[0..listMsgProcessorMaxLen-1, MsgProcessorPtr]
    thread: ptr TThread[MsgLooperPtr]

# Global initialization lock and cond use to have newMsgLooper not return
# until looper has startend and MsgLooper is completely initialized.
var
  gInitLock: TLock
  gInitCond: TCond

gInitLock.initLock()
gInitCond.initCond()

proc looper(ml: MsgLooperPtr) =
  let
    prefix = ml.name & ".looper:"

  proc dbg(s: string) {.inline.} =
    when DBG: echo prefix & s

  when DBG: dbg "+"

  gInitLock.acquire()
  block:
    when DBG: dbg "initializing"
    # initialize MsgLooper
    ml.listMsgProcessorLen = 0
    ml.listMsgProcessor = cast[ptr array[0..listMsgProcessorMaxLen-1,
              MsgProcessorPtr]](allocShared(sizeof(MsgProcessorPtr) * listMsgProcessorMaxLen))
    ml.lock = cast[ptr TLock](allocShared(sizeof(TLock)))
    ml.lock[].initLock()
    ml.cond = cast[ptr TCond](allocShared(sizeof(TCond)))
    ml.cond[].initCond()
    when DBG: dbg "signal gInitCond"
    ml.initialized = true;
    gInitCond.signal()
  gInitLock.release()

  # BUG: What happens when the list changes while we're iterating in these loops!

  ml.lock[].acquire
  while not ml.done:
    when DBG: dbg "TOL ml.listMsgProcessorLen=" & $ml.listMsgProcessorLen
    # Check if there are any messages to process
    var processedAtLeastOneMsg = false
    for idx in 0..ml.listMsgProcessorLen-1:
      var mp = ml.listMsgProcessor[idx]
      var msg = mp.mq.rmvHeadNonBlockingNolock()
      if msg != nil:
        processedAtLeastOneMsg = true
        when DBG: dbg "processing msg=" & $msg
        mp.pm(msg)
        # Cannot assume msg is valid here

    if not processedAtLeastOneMsg:
      # No messages to process so wait
      when DBG: dbg "waiting"
      ml.cond[].wait(ml.lock[])
      when DBG: dbg "done-waiting"
  ml.lock[].release
  when DBG: dbg "-"


proc newMsgLooper*(name: string): MsgLooperPtr =
  proc dbg(s: string) =
    echo name & ".newMsgLooper:" & s
  ## newMsgLooper does not return until the looper has started and
  ## everything is fully initialized

  when DBG: dbg "+"

  # Use a global to coordinate initialization of the looper
  # We may want to make a MsgLooper an untracked structure
  # in the future.
  gInitLock.acquire()
  block:
    result = cast[MsgLooperPtr](allocShared(sizeof(MsgLooper)))
    result.name = name
    result.initialized = false;

    when DBG: dbg "Using createThread"
    result.thread = cast[ptr TThread[MsgLooperPtr]](allocShared(sizeof(TThread[MsgLooperPtr])))
    createThread(result.thread[], looper, result)

    while (not result.initialized):
      when DBG: dbg "waiting on gInitCond"
      gInitCond.wait(gInitLock)
    when DBG: dbg "looper is initialized"
  gInitLock.release()

  when DBG: dbg "-"

proc delMsgLooper*(ml: MsgLooperPtr) =
  ## kills the message looper, andd message processors
  ## associated witht he looper will not receive any further
  ## messages and all queued up message are lost.
  ## So use this with care!!
  proc dbg(s:string) =
    echo ml.name & ".delMsgLooper:" & s

  when DBG: dbg "DOES NOTHING YET"

proc addProcessMsg*(ml: MsgLooperPtr, pm: ProcessMsg, qp: QueuePtr) =
  var mq = cast[MsgQueuePtr](qp)
  proc dbg(s:string) =
    echo ml.name & ".addMsgProcessor:" & s
  when DBG: dbg "+"
  ml.lock[].acquire()
  when DBG: dbg "acquired"
  if ml.listMsgProcessorLen < listMsgProcessorMaxLen:
    when DBG: dbg "...."
    var mp = cast[MsgProcessorPtr](allocShared(sizeof(MsgProcessor)))
    mp.mq = mq
    mp.pm = pm
    ml.listMsgProcessor[ml.listMsgProcessorLen] = mp
    ml.listMsgProcessorLen += 1
    ml.cond[].signal()
  else:
    doAssert(ml.listMsgProcessorLen >= listMsgProcessorMaxLen)

  ml.lock[].release()
  when DBG: dbg "-"

