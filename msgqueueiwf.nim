# Wait free/Thread safe Msg Queue modeled after Dimitry Vyukov's intrusive
# MPSC algorithm here:
#   http://www.1024cores.net/home/lock-free-algorithms/queues/intrusive-mpsc-node-based-queue
import msg, msgarena, locks, strutils

const DBG = false

type
  MsgQueue* = object of Queue
    name*: string
    head*: MsgPtr
    tail*: MsgPtr
    stub*: MsgPtr
  MsgQueuePtr* = ptr MsgQueue

proc `$`*(mq: MsgQueuePtr): string =
  result =
    if mq == nil:
      "<nil>"
    else:
      "{" & $mq.name & ":" &
        " head=" & $mq.head &
        " tail=" & $mq.tail &
        " stub=" & $mq.stub &
      "}"

proc isEmpty(mq: MsgQueuePtr): bool {.inline.} =
  var head = mq.head
  var next = atomicLoadN(addr head.next, ATOMIC_ACQUIRE)
  result = next == nil

proc newMsgQueue*(name: string, stub: MsgPtr): MsgQueuePtr =
  ## Create a new MsgQueue
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  proc dbg(s:string) = echo name & ".newMsgQueue(name,stub):" & s
  when DBG: dbg "+"
  mq.name = name
  stub.next = nil
  mq.head = stub
  mq.tail = stub
  mq.stub = stub
  result = cast[MsgQueuePtr](mq)
  when DBG: dbg "-"

proc delMsgQueue*(qp: QueuePtr) =
  var mq = cast[MsgQueuePtr](qp)
  proc dbg(s:string) = echo mq.name & ".delMsgQueue:" & s
  when DBG: dbg "+"
  doAssert(mq.isEmpty())
  delMsg(mq.stub)
  mq.head = nil
  mq.tail = nil
  mq.stub = nil
  GcUnref(mq.name)
  deallocShared(mq)
  when DBG: dbg "-"

proc addTail*(q: QueuePtr, msg: MsgPtr): bool =
  ## Add msg to tail. Iif this was added to an
  ## empty queue return true
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".addTail:" & s
  when DBG: dbg "+ msg=" & $msg & " mq=" & $mq
  msg.next = nil;
  # serialization-piont wrt to the single consumer, acquire-release
  var prevTail = atomicExchangeN(addr mq.tail, msg, ATOMIC_ACQ_REL)
  atomicStoreN(addr prevTail.next, msg, ATOMIC_RELEASE)
  result = prevTail == mq.stub
  when DBG: dbg "- result=" & $result & " mq=" & $mq

proc rmvHeadNonBlocking*(q: QueuePtr): MsgPtr =
  ## Return head or nil if empty
  ## May only be called from consumer
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".rmvHeadNonBlocking:" & s
  when DBG: dbg "+"
  try:
    var head = mq.head
    var next = head.next
    if head == mq.stub:
      if next == nil:
        when DBG: dbg " head == stub and next == nil: empty return nil"
        return nil
      when DBG: dbg " head == stub advance head"
      mq.head = next
      head = next
      next = next.next
    if next != nil:
      when DBG: dbg " next != nil advance again return head"
      mq.head = next
      return head
    var tail = mq.tail
    if tail != head:
      when DBG: dbg " tail != head return nil"
      return nil
    when DBG: dbg " tail == head add stub"
    discard addTail(q, mq.stub)
    next = head.next
    if next != nil:
      when DBG: dbg " head.next != nil update head return head"
      mq.head = next
      return head
    when DBG: dbg " at bottom return nil"
    return nil
  finally:
    when DBG: dbg "- msg=" & (if result == nil: "<nil>" else: $result) & " mq=" & $mq
