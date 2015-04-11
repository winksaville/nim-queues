## The MsgArena manages getting and returning message from memory
## in a thread safe manner and so maybe shared by multipel threads.
import msg, locks, strutils

const
  msgArenaSize = 32

type
  MsgArena* = object
    lock: TLock
    msgCount: int
    msgArray: ptr array[msgArenaSize, MsgPtr]

  MsgArenaPtr* = ptr MsgArena

# Forward declarations

proc `$`*(ma: MsgArenaPtr): string

# private procs

proc newMsg(cmdVal: int32, dataSize: int): MsgPtr =
  ## Allocate a new Msg.
  ## TODO: Allow dataSize other than zero
  result = cast[MsgPtr](allocShared(sizeof(Msg)))
  result.cmd = cmdVal
  result.next = nil

proc delMsg*(msg: MsgPtr) =
  ## Deallocate a msg
  ## TODO: handle data size
  freeShared(msg)

proc getMsgArrayPtr(ma: MsgArenaPtr): ptr array[msgArenaSize, MsgPtr] =
  ## Assume ma.lock is acquired
  if ma.msgArray == nil:
    ma.msgArray = cast[ptr array[msgArenaSize, MsgPtr]]
                    (allocShared0(sizeof(MsgPtr) * msgArenaSize))
  result = ma.msgArray

# public procs

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
          msgStr &= $ma.msgArray[idx]
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
        var msg = ma.msgArray[idx]
        delMsg(msg)
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
      result = msgA[ma.msgCount]
      result.cmd = cmd
    else:
      result = newMsg(cmd, dataSize)
  ma.lock.release()

proc retMsg*(ma: MsgArenaPtr, msg: MsgPtr) =
  ma.lock.acquire()
  block:
    var msgA = ma.getMsgArrayPtr()
    if ma.msgCount < msgA[].len():
      msgA[ma.msgCount] = msg
      ma.msgCount += 1
    else:
      delMsg(msg)
      
  ma.lock.release()
