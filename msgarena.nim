## The MsgArena manages getting and returning message from memory
## in a thread safe manner and so maybe shared by multipel threads.
import msg, locks, strutils

const
  msgArenaSize = 32

type
  MsgNodePtr* = ptr MsgNode
  MsgNode* = object
    next*: MsgNodePtr
    msg*: MsgPtr

  MsgArenaPtr* = ptr MsgArena
  MsgArena* = object
    lock: TLock
    msgCount: int
    msgArray: ptr array[msgArenaSize, MsgPtr]
    msgNodeCount: int
    msgNodeArray: ptr array[msgArenaSize, MsgNodePtr]


# Forward declarations

proc `$`*(ma: MsgArenaPtr): string

# private procs

proc newMsg(cmdVal: int32, dataSize: int): MsgPtr =
  ## Allocate a new Msg.
  ## TODO: Allow dataSize other than zero
  result = cast[MsgPtr](allocShared(sizeof(Msg)))
  result.cmd = cmdVal
  result.next = nil

proc newMsgNode(next: MsgNodePtr, msg: MsgPtr): MsgNodePtr =
  ## Allocate a new MsgNode.
  result = cast[MsgNodePtr](allocShared0(sizeof(MsgNode)))
  result.next = next
  result.msg = msg

proc delMsg*(msg: MsgPtr) =
  ## Deallocate a Msg
  ## TODO: handle data size
  freeShared(msg)

proc delMsgNode*(mn: MsgNodePtr) =
  ## Deallocate a MsgNode
  freeShared(mn)

proc getMsgArrayPtr(ma: MsgArenaPtr): ptr array[msgArenaSize, MsgPtr] =
  ## Assume ma.lock is acquired
  if ma.msgArray == nil:
    ma.msgArray = cast[ptr array[msgArenaSize, MsgPtr]]
                    (allocShared0(sizeof(MsgPtr) * msgArenaSize))
  result = ma.msgArray

proc getMsgNodeArrayPtr(ma: MsgArenaPtr): ptr array[msgArenaSize, MsgNodePtr] =
  ## Assume ma.lock is acquired
  if ma.msgNodeArray == nil:
    ma.msgNodeArray = cast[ptr array[msgArenaSize, MsgNodePtr]]
                    (allocShared0(sizeof(MsgNodePtr) * msgArenaSize))
  result = ma.msgNodeArray

# public procs

proc ptrToStr(label: string, p: pointer): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

proc nextToStr(mn: MsgNodePtr): string =
  ptrToStr("next", mn.next)

proc `$`*(mn: MsgNodePtr): string =
  if mn == nil:
    result = "<nil>"
  else:
    result = "{" &
               ptrToStr("mn:", mn) &
               ptrToStr(" next=", mn.next) &
               ptrToStr(" msg=", mn.msg) &
             "}"

proc `$`*(ma: MsgArenaPtr): string =
  if ma == nil:
    result = "<nil>"
  else:
    ma.lock.acquire()
    block:
      var msgStr = "{"
      if ma.msgArray != nil:
        for idx in 0..ma.msgCount-1:
          msgStr &= $ma.msgArray[idx]
          if idx < ma.msgCount-1:
            msgStr &= ", "
      msgStr &= "}"
      var msgNodeStr = "{"
      if ma.msgNodeArray != nil:
        for idx in 0..ma.msgNodeCount-1:
          msgNodeStr &= $ma.msgNodeArray[idx]
          if idx < ma.msgNodeCount-1:
            msgNodeStr &= ", "
      msgNodeStr &= "}"
      result = "{msgArray:" & $ma.msgCount & " " & msgStr &
                " msgNodeArray:" & $ma.msgNodeCount & " " & msgNodeStr & "}"
    ma.lock.release()

proc newMsgArena*(): MsgArenaPtr =
  result = cast[MsgArenaPtr](allocShared0(sizeof(MsgArena)))
  result.lock.initLock()
  result.msgCount = 0;
  result.msgNodeCount = 0;

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

proc getMsgNode*(ma: MsgArenaPtr, next: MsgNodePtr, msg: MsgPtr): MsgNodePtr =
  ## TODO: Make wait free!!!!!!
  ma.lock.acquire()
  block:
    var mnAry = ma.getMsgNodeArrayPtr()
    if ma.msgNodeCount > 0:
      ma.msgNodeCount -= 1
      result = mnAry[ma.msgNodeCount]
      result.next = next
      result.msg = msg
    else:
      result = newMsgNode(next, msg)

  ma.lock.release()

proc retMsgNode*(ma: MsgArenaPtr, mn: MsgNodePtr) =
  ## TODO: Make wait free!!!!!!
  ma.lock.acquire()
  block:
    var mnAry = ma.getMsgNodeArrayPtr()
    if ma.msgNodeCount < mnAry[].len():
      mn.next = nil
      mn.msg = nil
      mnAry[ma.msgNodeCount] = mn
      ma.msgNodeCount += 1
    else:
      delMsgNode(mn)
  ma.lock.release()
