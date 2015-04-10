import locks, strutils

type

  QueuePtr* = ptr Queue
  Queue* = object of RootObj

  MsgPtr* = ptr Msg
  Msg* = object of RootObj
    next*: MsgPtr
    rspQ*: QueuePtr
    cmd*: int32

proc nextToStr(msg): string =
  if msg.next == nil:
    result = " next=<nil>"
  else:
    result = " next=0x" & toHex(cast[int](msg.next), sizeof(int)*2)

proc rspQToStr(msg): string =
  if msg.rspQ == nil:
    result = " rspQ=<nil>"
  else:
    result = " rspQ=0x" & toHex(cast[int](msg.rspQ), sizeof(int)*2)

proc `$`*(msg: MsgPtr): string =
  if msg == nil:
    result = "<nil>"
  else:
    result = "{msg:0x" & toHex(cast[int](msg), sizeof(int)*2) &
              nextToStr(msg) &
              rspQToStr(msg) &
              " cmd=" & $msg.cmd & "}"

