# Wait free/Thread safe Msg Queue modeled after Dimitry Vyukov's non intrusive
# MPSC algorithm here:
#   http://www.1024cores.net/home/lock-free-algorithms/queues/non-intrusive-mpsc-node-based-queue
import msg, msgarena, locks, strutils

const DBG = false

type
  MsgQueue* = object of Queue
    name*: string
    ownsCondAndLock*: bool
    cond*: ptr TCond
    lock*: ptr TLock
    stubArena: MsgArenaPtr
    head*: MsgPtr
    tail*: MsgPtr
  MsgQueuePtr* = ptr MsgQueue

proc `$`*(mq: MsgQueuePtr): string =
  result =
    if mq == nil:
      "<nil>"
    else:
      "{" & $mq.name & ":" &
        " head=" & $mq.head &
        " tail=" & $mq.tail &
      "}"

# Forward declaration
proc emptyNoLock*(mq: MsgQueuePtr): bool {.inline.}

proc newMsgQueue*(name: string, cond: ptr TCond, lock: ptr TLock, stub: MsgPtr): MsgQueuePtr =
  ## Create a new MsgQueue passing the initialized condition and lock
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  proc dbg(s:string) =
    echo name & ".newMsgQueue(name,cond,lock,stub):" & s
  when DBG: dbg "+"
  mq.name = name
  mq.ownsCondAndLock = false
  mq.cond = cond
  mq.lock = lock
  stub.next = nil
  mq.head = stub
  mq.tail = stub
  result = cast[MsgQueuePtr](mq)
  when DBG: dbg "-"

proc newMsgQueue*(name: string, stub: MsgPtr): MsgQueuePtr =
  proc dbg(s:string) =
    echo name & ".newMsgQueue(name,stub):" & s
  when DBG: dbg "+"
  var
    cond = cast[ptr TCond](allocShared(sizeof(TCond)))
    lock = cast[ptr TLock](allocShared(sizeof(TLock)))
  cond[].initCond()
  lock[].initLock()
  result = newMsgQueue(name, cond, lock, stub)
  result.ownsCondAndLock = true
  when DBG: dbg "-"

proc delMsgQueue*(mq: MsgQueuePtr) =
  proc dbg(s:string) =
    echo mq.name & ".delMsgQueue:" & s
  when DBG: dbg "+"
  doAssert(mq.emptyNoLock())
  delMsg(mq.head)
  mq.head = nil
  mq.tail = nil
  GcUnref(mq.name)
  deallocShared(mq)
  when DBG: dbg "-"

proc delMsgQueue*(qp: QueuePtr) =
  delMsgQueue(cast[MsgQueuePtr](qp))

proc emptyNoLock*(mq: MsgQueuePtr): bool =
  proc dbg(s:string) =
    echo mq.name & ".emptyNoLock:" & s
  when DBG: dbg "+"
  ## Assume a lock is held outside
  ## TODO: NOT atomic
  result = mq.head == mq.tail
  when DBG: dbg "- " & $result

proc rmvHeadNonBlockingNoLock*(mq: MsgQueuePtr): MsgPtr =
  ## Return head or nil if empty
  proc dbg(s:string) =
    echo mq.name & ".rmvHeadNonBlockingNoLock:" & s
  when DBG: dbg "+"
  result = mq.head
  var next = atomicLoadN(addr result.next, ATOMIC_ACQUIRE) # serialization-point wrt producers, acquire
  if next != nil:
    mq.head = next
  else:
    result = nil
  when DBG: echo "mq=", mq
  when DBG: dbg "- msg=" & $result

proc addTail*(q: QueuePtr, msg: MsgPtr) =
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) =
    echo mq.name & ".addTail:" & s
  when DBG: dbg "+ msg=" & $msg
  msg.next = nil;
  var prev = atomicExchangeN(addr mq.tail, msg, ATOMIC_ACQ_REL)
  atomicStoreN(addr prev.next, msg, ATOMIC_RELEASE)
  when DBG: echo "mq=", mq
  when DBG: dbg "- msg=" & $msg

proc rmvHead*(q: QueuePtr): MsgPtr =
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) =
    echo mq.name & ".rmvHead:" & s
  when DBG: dbg "+"
  result = mq.rmvHeadNonBlockingNoLock()
  if result == nil:
    mq.lock[].acquire()
    block:
      while emptyNoLock(mq):
        when DBG: dbg "waiting"
        mq.cond[].wait(mq.lock[])
      when DBG: dbg "going"
      result = mq.rmvHeadNonBlockingNoLock()
    mq.lock[].release()
  when DBG: echo "mq=", mq
  when DBG: dbg "- msg=" & $result

proc rmvHeadNonBlocking*(mq: MsgQueuePtr): MsgPtr =
  result = rmvHeadNonBlockingNoLock(mq)
