import msgarena, msgqueue

echo "t1.nim"

var
  ma = newMsgArena()
  mq1 = newMsgQueue("mq1")
  msg1 = ma.getMsg(1, 0)
  msg2 = ma.getMsg(2, 0)

echo "ma=", ma
echo "mq1", mq1

msg1.next = msg2
echo "msg1=", msg1, " msg2=", msg2

mq1.addTail(msg1)
echo "mq1 after adding msg1", mq1

mq1.addTail(msg2)
echo "mq1 after adding msg2", mq1

