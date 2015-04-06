# A MsgArena manages getting and returning messages from memory
# The MsgArena is thread safe and shared so they maybe used
# across threads.
import locks, strutils

const
  msgArenaSize = 32

type
  MsgPtr* = ptr Msg
  Msg* = object of RootObj
    next*: MsgPtr
    cmd*: int32

  MsgArena* = object
    lock: TLock
    msgCount: int
    msgArray: ptr array[msgArenaSize, MsgPtr]

  MsgArenaPtr* = ptr MsgArena

# private procs
proc newMsg(cmdVal: int32, dataSize: int): MsgPtr =
  result = cast[MsgPtr](alloc(sizeof(Msg)))
  result.cmd = cmdVal

proc getMsgArrayPtr(ma: MsgArenaPtr): ptr array[msgArenaSize, MsgPtr] =
  ### Assume ma.lock is acquired
  if ma.msgArray == nil:
    ma.msgArray = cast[ptr array[msgArenaSize, MsgPtr]]
                    (allocShared(sizeof(MsgPtr) * msgArenaSize))
  result = ma.msgArray

## public procs

proc `$`*(msg: MsgPtr): string =
  result = if msg == nil: "<nil>" else: "{msg:0x" &
        toHex(cast[int](msg), sizeof(int)*2) &
        (if msg.next == nil: " next=<nil>" else:
          " next=0x" & toHex(cast[int](msg.next), sizeof(int)*2)) &
        " cmd=" & $msg.cmd & "}"

proc `$`*(ma: MsgArenaPtr): string =
  if ma == nil:
    result = "<nil>"
  else:
    ma.lock.acquire()
    block:
      var msgStr = "{"
      if ma.msgArray != nil:
        for idx in 0..ma.msgCount-1:
          # probably should do a sequence ??
          msgStr &= $(cast[MsgPtr](ma.msgArray[idx]))
          if idx < ma.msgCount-1:
            msgStr &= ", "
      msgStr &= "}"
      result = "{" & $ma.msgCount & ", " & msgStr & "}"
    ma.lock.release()

proc newMsgArena*(): MsgArenaPtr =
  result = cast[MsgArenaPtr](allocShared0(sizeof(MsgArena)))
  result.lock.initLock()
  result.msgCount = 0;

proc delMsgArena*(ma: MsgArenaPtr) =
  ma.lock.acquire()
  block:
    if ma.msgArray != nil:
      for idx in 0..ma.msgCount-1:
        var msg = cast[MsgPtr](ma.msgArray[idx])
        deallocShared(msg)
      deallocShared(ma.msgArray)
  ma.lock.release()
  ma.lock.deinitLock()
  deallocShared(ma)

proc getMsg*(ma: MsgArenaPtr, cmd: int32, dataSize: int): MsgPtr =
  ma.lock.acquire()
  block:
    var msgA = ma.getMsgArrayPtr()
    if ma.msgCount > 0:
      ma.msgCount -= 1
      result = cast[MsgPtr](msgA[ma.msgCount])
      result.cmd = cmd
    else:
      result = cast[MsgPtr](newMsg(cmd, dataSize))
  ma.lock.release()

proc retMsg*(ma: MsgArenaPtr, msg: MsgPtr) =
  ma.lock.acquire()
  block:
    var msgA = ma.getMsgArrayPtr()
    if ma.msgCount < msgA[].len():
      msgA[ma.msgCount] = cast[MsgPtr](msg)
      ma.msgCount += 1
    else:
      doAssert(ma.msgCount < msgA[].len())
  ma.lock.release()
