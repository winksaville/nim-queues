# Thread safe Msg Queue
import msgarena, locks, strutils

#when not defined(release):
#  const DBG = true
#else:
#  const DBG = false

const DBG = false
echo "msgqueue: DBG=", DBG

type
  MsgQueuePtr* = ptr MsgQueue

  MsgQueue* = object
    name: string
    ownsCondAndLock: bool
    cond: ptr TCond
    lock: ptr TLock
    head: MsgPtr
    tail: MsgPtr

proc `$`*(mq: MsgQueuePtr): string =
  result =
    if mq == nil:
      "<nil>"
    else:
      "{" & $mq.name & ":" &
        " ownsCondAndLock=" & $mq.ownsCondAndLock &
        " head=" & $mq.head &
        " tail=" & $mq.tail &
      "}"

proc newMsgQueue*(name: string, cond: ptr TCond, lock: ptr TLock): MsgQueuePtr =
  ## Create a new MsgQueue passing the initialized condition and lock
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  proc dbg(s:string) =
    echo name & ".newMsgQueue(name,cond,lock):" & s
  when DBG: dbg "+"
  mq.name = name
  mq.ownsCondAndLock = false
  mq.cond = cond;
  mq.lock = lock;
  mq.head = nil
  mq.tail = nil
  result = cast[MsgQueuePtr](mq)
  when DBG: dbg "-"

proc newMsgQueue*(name: string): MsgQueuePtr =
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  proc dbg(s:string) =
    echo name & ".newMsgQueue(name):" & s
  when DBG: dbg "+"
  mq.name = name
  mq.ownsCondAndLock = true
  mq.cond = cast[ptr TCond](allocShared(sizeof(TCond)))
  mq.cond[].initCond()
  mq.lock = cast[ptr TLock](allocShared(sizeof(TLock)))
  mq.lock[].initLock()
  mq.head = nil
  mq.tail = nil
  result = cast[MsgQueuePtr](mq)
  when DBG: dbg "-"

proc delMsgQueue*(mq: MsgQueuePtr) =
  proc dbg(s:string) =
    echo mq.name & ".delMsgQueue:" & s
  when DBG: dbg "+"
  assert(mq.head == nil)
  assert(mq.tail == nil)
  if mq.ownsCondAndLock:
    mq.cond[].deinitCond()
    freeShared(mq.cond)
    mq.lock[].deinitLock()
    freeShared(mq.lock)
  GcUnref(mq.name)
  deallocShared(mq)
  when DBG: dbg "-"

proc emptyNoLock*(mq: MsgQueuePtr): bool {.inline.} =
  ## Assume a lock is held outside
  result = mq.head == nil

proc rmvHeadNoLock(mq: MsgQueuePtr): MsgPtr =
  proc dbg(s:string) =
    echo mq.name & ".rmvHeadNoLock:" & s
  when DBG: dbg "+"
  result = mq.head
  mq.head = result.next
  result.next = nil
  if emptyNoLock(mq):
    mq.tail = nil
  when DBG: dbg "- msg=" & $result

proc rmvHeadNonBlockingNoLock*(mq: MsgQueuePtr): MsgPtr =
  proc dbg(s:string) =
    echo mq.name & ".rmvHeadNonBlocking:" & s
  when DBG: dbg "+"
  block:
    if emptyNoLock(mq):
      result = nil
    else:
      result = mq.rmvHeadNoLock()
  when DBG: dbg "- msg=" & $result

proc addTail*(mq: MsgQueuePtr, msg: MsgPtr) =
  proc dbg(s:string) =
    echo mq.name & ".addTail:" & s
  when DBG: dbg "+ msg=" & $msg
  mq.lock[].acquire()
  when DBG: dbg "got lock"
  block:
    msg.next = nil
    if emptyNoLock(mq):
      mq.head = msg
      mq.tail = msg
      when DBG: dbg "add msg to empty and signal"
      mq.cond[].signal()
    else:
      mq.tail.next = msg
      mq.tail = msg
      when DBG: dbg "add msg to non-empty NO signal"
  when DBG: dbg "releasing lock"
  mq.lock[].release()
  when DBG: echo "mq=", mq
  when DBG: dbg "- msg=" & $msg

proc rmvHead*(mq: MsgQueuePtr): MsgPtr =
  proc dbg(s:string) =
    echo mq.name & ".rmvHead:" & s
  when DBG: dbg "+"
  mq.lock[].acquire()
  block:
    while emptyNoLock(mq):
      when DBG: dbg "waiting"
      mq.cond[].wait(mq.lock[])
    when DBG: dbg "going"
    result = mq.rmvHeadNoLock()
  mq.lock[].release()
  when DBG: dbg "- msg=" & $result

proc rmvHeadNonBlocking*(mq: MsgQueuePtr): MsgPtr =
  mq.lock[].acquire()
  block:
    result = rmvHeadNonBlockingNoLock(mq)
  mq.lock[].release()
