#!/bin/bash
#andrew ling  2016/09/20

#init the nic`s bandwidth rule
init_dev_bandwidth() {
  local dev=$1
  local rate=$2
  local ceil=$3
  mount -t cgroup net_cls -o net_cls /cgroup/net_cls/
  tc qdisc del dev $dev root
  tc qdisc add dev $dev root handle 1: htb && tc class add dev $dev parent 1: classid 1: htb rate ${rate}kbit ceil ${ceil}kbit && tc filter add dev $dev protocol ip parent 1:0 prio 1 handle 1: cgroup
  
  return $?
}

#tc class add dev eth0 parent 1: classid 1:3 htb rate 10mbit 
set_bandwidth_class() {
  local op=
  local dev=$2
  local classid=$3
  local rate=$4
  local ceil=$5
  if [ "$1" == "A" ]
  then
    op="add"
  elif [ "$1" == "D" ]; then
    op="del"
  elif [ "$1" == "U" ]; then
    op="change"
  fi

  tc class $op dev $dev parent 1: classid 1:$classid htb rate ${rate}kbit ceil ${ceil}kbit
  return $? 

}

set_cgroup() {
  local op=
  local cgroup=$2
  if [ "$1" == "A" ]
  then
    op="cgcreate"
  elif [ "$1" == "D" ]; then
    op="cgdelete"
  fi
  $op -g net_cls:$cgroup
  return $?

}

connet_tc_cgroup() {
  local op=
  local classid_0x=$2
  local cgroup=$3
  local pid=$4
  if [ "$1" == "A" ]
  then
    echo 0x1${classid_0x}
    echo 0x1${classid_0x} > /cgroup/net_cls/$cgroup/net_cls.classid && echo $pid > /cgroup/net_cls/$cgroup/tasks
    return $?
  elif [ "$1" == "D" ]; then
    echo '' > /cgroup/net_cls/$cgroup/net_cls.classid && echo $pid > /cgroup/net_cls/tasks
    return $?
  fi
  return 0

}

op=""
tcflag=
cgroupflag=
relevanceflag=

while getopts 'FADUTCRn:r:c:i:g:I:p:h' OPTION
do
  case $OPTION in
    F) Fflag=1
      ;;
    A) Aflag=1
      op="A"
      ;;
    D) Dflag=1
      op="D"
      ;;
    U) Uflag=1
      op="U"
      ;;
    T) tcflag=1
      ;;
    C) cgroupflag=1
      ;;
    R) relevanceflag=1
      ;;
    n) dev="$OPTARG"
      ;;
    r) rate="$OPTARG"
      ;;
    c) ceil="$OPTARG"
      ;;
    i) classid="$OPTARG"
      ;;
    g) cgroup="$OPTARG"
      ;;
    I) classid_0x="$OPTARG"
      ;;
    p) pid="$OPTARG"
      ;;
    h) echo $"Usage : $0 {-F: first init|-A|-D|-U|-T: use tc|C: use cgroup|R:use TC+cgroup|n:dev number|r:rate|c:ceil|i:classid|g:cgroup|I:classid_0x|p:pid|-h help}"
      exit 2
      ;;
    ?) echo $"Usage : $0 {-F: first init|-A|-D|-U|-T: use tc|C: use cgroup|R:use TC+cgroup|n:dev number|r:rate|c:ceil|i:classid|g:cgroup|I:classid_0x|p:pid|-h help}"
      exit 2
      ;;
  esac
done

if [ "$Fflag" == "1" ]
then
  #初始化
  init_dev_bandwidth $dev $rate $ceil
  exit $?
fi

if [ "$Aflag$Dflag$Uflag" != "1" ]
then
    exit 2
fi

if [ "$tcflag$cgroupflag$relevanceflag" != "1" ]
then
    exit 2
fi

#操作TC
if [ "$tcflag" == "1" ]; then
  set_bandwidth_class $op $dev $classid $rate $ceil
  if [ $? -ne 0 ]; then
    exit $?
  fi
fi

#操作cgroup
if [ "$cgroupflag" == "1" ]; then
  set_cgroup $op $cgroup
  if [ $? -ne 0 ]; then
    exit $?
  fi
fi

#操作TC+cgroup的关系
if [ "$relevanceflag" == "1" ]; then
  connet_tc_cgroup $op $classid_0x $cgroup $pid
  if [ $? -ne 0 ]; then
    exit $?
  fi
fi

exit 0
