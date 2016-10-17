#!/bin/bash
#andrew ling  2016/09/22

#init the nic`s bandwidth rule
init_dev_bandwidth() {
  local dev=$1
  local rate=$2
  local ceil=$3
  tc qdisc del dev $dev root
  umount /cgroup/net_cls/
  
  (tc qdisc add dev $dev root handle 1: htb) && 
  (tc class add dev $dev parent 1: classid 1: htb rate ${rate}kbit ceil ${ceil}kbit) && 
  (tc filter add dev $dev protocol ip parent 1:0 prio 1 handle 1: cgroup) &&
  (mount -t cgroup net_cls -o net_cls /cgroup/net_cls/)
  return $?
}

update_dev_bandwidth() {
  local dev=$1
  local rate=$2
  local ceil=$3
  tc class change dev $dev parent 1: classid 1: htb rate ${rate}kbit ceil ${ceil}kbit
  return $?
}

clean_dev_bandwidth() {
  local dev=$1
  tc qdisc del dev $dev root
  #del all the cgroup
  files=$(ls /cgroup/net_cls |grep $dev)
  for file in $files
  do
    cgdelete -g net_cls:$file
    if [ $? -ne 0 ]; then
      exit $?
    fi
  done
  umount /cgroup/net_cls/
  return $?
}

while getopts 'ADUn:r:c:h' OPTION
do
  case $OPTION in
    A) Aflag=1
      ;;
    D) Dflag=1
      ;;
    U) Uflag=1
      ;;
    n) dev="$OPTARG"
      ;;
    r) rate="$OPTARG"
      ;;
    c) ceil="$OPTARG"
      ;;
    h) echo $"Usage : $0 {-A|-D|-U|n:dev number|r:rate|c:ceil|-h help}"
      exit 2
      ;;
    ?) echo $"Usage : $0 {-A|-D|-U|n:dev number|r:rate|c:ceil|-h help}"
      exit 2
      ;;
  esac
done

if [ "$Aflag$Dflag$Uflag" != "1" ]
then
    exit 2
fi

if [ "$Aflag" == "1" ]
then
  #初始化
  init_dev_bandwidth $dev $rate $ceil
  exit $?
fi

if [ "$Uflag" == "1" ]
then
    update_dev_bandwidth $dev $rate $ceil
    exit $?
fi

if [ "$Dflag" == "1" ]
then
    clean_dev_bandwidth $dev
    exit $?
fi

exit 0
