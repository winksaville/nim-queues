# Wait free/Thread safe Msg Queue modeled after Dimitry Vyukov's non intrusive
# MPSC algorithm here:
#   http://www.1024cores.net/home/lock-free-algorithms/queues/non-intrusive-mpsc-node-based-queue
#
# At this time I couldn't figure out a good way for
# addTail to return a boolean indicating if the msg
# was added to an empty queue. The problem is empty
# is defined by head.next == nil but we add to the
# tail and in this MPSC queue we can look at to
# items that need to be atomic. So for now we'll not
# have that information.
import msg, msgarena, locks, strutils

const DBG = false

type
  MsgQueue* = object of Queue
    name*: string
    arena: MsgArenaPtr
    head*: MsgNodePtr
    tail*: MsgNodePtr
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

proc newMsgQueue*(name: string, arena: MsgArenaPtr): MsgQueuePtr =
  ## Create a new MsgQueue
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  proc dbg(s:string) = echo name & ".newMsgQueue(name,ma):" & s
  when DBG: dbg "+"

  mq.name = name
  mq.arena = arena
  var node = mq.arena.getMsgNode(nil, nil)
  mq.head = node
  mq.tail = node
  result = mq

  when DBG: dbg "- mq=" & $mq

proc delMsgQueue*(qp: QueuePtr) =
  var mq = cast[MsgQueuePtr](qp)
  proc dbg(s:string) = echo mq.name & ".delMsgQueue:" & s
  when DBG: dbg "+"

  doAssert(mq.isEmpty())
  delMsgNode(mq.head)
  mq.arena = nil
  mq.head = nil
  mq.tail = nil
  GcUnref(mq.name)
  deallocShared(mq)

  when DBG: dbg "-"

proc addTail*(q: QueuePtr, msg: MsgPtr) =
  ## Add msg to tail if this was added to an
  ## empty queue return true
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".addTail:" & s
  when DBG: dbg "+ msg=" & $msg & " mq=" & $mq

  var mn = mq.arena.getMsgNode(nil, msg)
  # serialization-piont wrt to the single consumer, acquire-release
  var prevTail = atomicExchangeN(addr mq.tail, mn, ATOMIC_ACQ_REL)
  when DBG: dbg "  prevTail=" & $prevTail
  atomicStoreN(addr prevTail.next, mn, ATOMIC_RELEASE)

  when DBG: dbg "- msg=" & $msg & " prevTail=" & $prevTail & " mn=" & $mn & " mq=" & $mq

proc rmvHead*(q: QueuePtr): MsgPtr =
  ## Return head or nil if empty
  ## May only be called from consumer
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".rmvHead:" & s
  when DBG: dbg "+ mq=" & $mq

  var head = mq.head
  when DBG: dbg " head=" & $head
  # serialization-point wrt producers, acquire
  var next = atomicLoadN(addr head.next, ATOMIC_ACQUIRE)
  when DBG: dbg " next=" & $next
  if next != nil:
    result = next.msg
    when DBG: dbg " next != nil result = next.msg result=" & $result
    mq.head = next
    when DBG: dbg " next != nil mq.head = next mq=" & $mq
    mq.arena.retMsgNode(head)
    when DBG: dbg " next != nil return head to arena mq.arena=" & $mq.arena
  else:
    when DBG: dbg " next == nil result=nil, mq=" & $mq
    result = nil
  when DBG: dbg "- msg=" & $result & " mq=" & $mq

when isMainModule:
  import unittest

  suite "test msgqueueniwf":
    var ma: MsgArenaPtr

    setup:
      ma = newMsgArena()
    teardown:
      ma.delMsgArena()

    test "test new queue is empty":
      var mq = newMsgQueue("mq", ma)
      var msg = mq.rmvHead()
      check(mq.isEmpty())

    test "test add, rmv":
      var mq = newMsgQueue("mq", ma)
      var msg = ma.getMsg(1, 0)
      mq.addTail(msg)
      check(not mq.isEmpty())

      msg = mq.rmvHead()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

    test "test add, rmv, add, add, rmv, rmv":
      var mq = newMsgQueue("mq", ma)
      var msg = ma.getMsg(1, 0)
      mq.addTail(msg)
      check(not mq.isEmpty())

      msg = mq.rmvHead()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

      msg = ma.getMsg(2, 0)
      mq.addTail(msg)
      check(not mq.isEmpty())
      msg = ma.getMsg(3, 0)
      mq.addTail(msg)
      check(not mq.isEmpty())

      msg = mq.rmvHead()
      check(msg.cmd == 2)
      check(not mq.isEmpty())
      ma.retMsg(msg)
      msg = mq.rmvHead()
      check(msg.cmd == 3)
      check(mq.isEmpty())
      ma.retMsg(msg)
