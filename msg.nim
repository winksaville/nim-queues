import locks, strutils

type

  QueuePtr* = ptr Queue
  Queue* = object of RootObj

  MsgPtr* = ptr Msg
  Msg* = object of RootObj
    next*: MsgPtr
    rspQ*: QueuePtr
    cmd*: int32

proc ptrToStr(label: string, p: pointer): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

proc `$`*(msg: MsgPtr): string =
  if msg == nil:
    result = "<nil>"
  else:
    result = "{" &
                ptrToStr("msg:", msg) &
                ptrToStr(" next=", msg.next) &
                ptrToStr(" rspQ=", msg.rspQ) &
                " cmd=" & $msg.cmd &
              "}"

