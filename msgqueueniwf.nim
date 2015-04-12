# Wait free/Thread safe Msg Queue modeled after Dimitry Vyukov's non intrusive
# MPSC algorithm here:
#   http://www.1024cores.net/home/lock-free-algorithms/queues/non-intrusive-mpsc-node-based-queue
#
# THIS IS CURRENTLY BROKEN IT DOES NOT RETURN MSGS PROPERLY.
# The reason is the algorithm is "non-intrusive" and I need
# to provide a "stub" associated with each message, but
# this doen't currently do that.
#
# I think what I need to do is create a "non-intrusive" msgarena
# which will return a header and a message as two entities.
# Another words msgarenaniwf.nim would return a header which
# has, at a mimimum, the next and MsgPtr. What I'm thinking at
# the moment is that the msg header would be one cache line long
# and maybe something like:
# const
#   CACHE_LINE_SIZE_IN_INTS = 8
#
# type
#   # This would be the cache aligned Stub
#   MsgStub = obect
#     next*: MsgPtr
#     msg*: MsgPtr
#     fill: array[1..CACHE_LINE_SIZE_IN_INTS-2, int]
#
#   # This would be the cache aligned Header as another alternative
#   # This is slower as we'd need to copy rspQ, cmd and other where
#   # and in MsgStub we'd only copy msg
#   MsgHeader = obect
#     next*: MsgPtr
#     rspQ*: QueuePtr
#     cmd: int
#     other: TAny
#     fill: array[1..CACHE_LINE_SIZE_IN_INTS-4, int]
#
import msg, msgarena, locks, strutils

const DBG = false

type
  MsgQueue* = object of Queue
    name*: string
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
  result = cast[MsgQueuePtr](mq)
  when DBG: dbg "-"

proc delMsgQueue*(qp: QueuePtr) =
  var mq = cast[MsgQueuePtr](qp)
  proc dbg(s:string) = echo mq.name & ".delMsgQueue:" & s
  when DBG: dbg "+"
  doAssert(mq.isEmpty())
  delMsg(mq.head)
  mq.head = nil
  mq.tail = nil
  GcUnref(mq.name)
  deallocShared(mq)
  when DBG: dbg "-"

proc brokenAddTail*(q: QueuePtr, msg: MsgPtr): bool =
  ## Add msg to tail if this was added to an
  ## empty queue return true
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".addTail:" & s
  when DBG: dbg "+ msg=" & $msg
  msg.next = nil;
  # serialization-piont wrt to the single consumer, acquire-release
  var prevTail = atomicExchangeN(addr mq.tail, msg, ATOMIC_ACQ_REL)
  atomicStoreN(addr prevTail.next, msg, ATOMIC_RELEASE)
  result = prevTail == nil
  when DBG: echo "mq=", mq
  when DBG: dbg "- msg=" & $msg

proc brokenRmvHeadNonBlocking*(q: QueuePtr): MsgPtr =
  ## Return head or nil if empty
  ## May only be called from consumer
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".rmvHeadNonBlocking:" & s
  when DBG: dbg "+"
  result = mq.head
  # serialization-point wrt producers, acquire
  var next = atomicLoadN(addr result.next, ATOMIC_ACQUIRE)
  if next != nil:
    mq.head = next
  else:
    result = nil
  when DBG: echo "mq=", mq
  when DBG: dbg "- msg=" & $result
