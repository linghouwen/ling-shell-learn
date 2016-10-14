#!/bin/bash
#andrew ling  2016/09/22

#返回的字符串信息使用逗号分隔
list_dev_bandwidth_info() {
  local dev=$1
  local bandwidth_info=

  local files=$(ls /cgroup/net_cls |grep $dev)
  for file in $files
  do
    #获取TC的信息和pid的信息
    local classid=${file#"$dev"}
    local rate=$(tc class show dev $dev|grep 'htb 1:'${classid}' parent'|awk -F' ' '{print $9}')
    local ceil=$(tc class show dev $dev|grep 'htb 1:'${classid}' parent'|awk -F' ' '{print $11}')
    local result="keyId:"${classid}" rate:"${rate}" ceil:"${ceil}" pids:"
    local pids=$(cat /cgroup/net_cls/$dev$classid/tasks)
    for pid in $pids
    do
      result=${result}${pid}","
    done
    if [ "$pids" != "" ]
    then
      result=${result%?}
    fi
      bandwidth_info="${bandwidth_info}${result};" 
  done

  echo $bandwidth_info
  #return $bandwidth_info

}

is_keyId_valid() {
  local keyId=$1
  if [ $keyId -gt 0 ] && [ $keyId -le 65535 ]
  then
       return 0
  else
       exit 2
  fi
}

set_bandwidth_rule() {
  local op=
  local dev=$2
  local rate=
  local ceil=
  local keyId=
  local pids=

  if [ "$1" == "A" ]
  then
    rate=$3
    ceil=$4
    keyId=$5
    pids=$6
    classid_0x=

    local string=$(echo "obase=16;$keyId"|bc)
    local length=${#string}
    if [ $length -eq 1 ]; then
      classid_0x=000${string}
    elif [ $length -eq 2 ]; then
      classid_0x=00${string}
    elif [ $length -eq 3 ]; then
      classid_0x=0${string}
    elif [ $length -eq 4 ]; then
      classid_0x=$string
    fi

    (tc class add dev $dev parent 1: classid 1:$keyId htb rate ${rate}kbit ceil ${ceil}kbit) && 
    (cgcreate -g net_cls:${dev}${keyId}) && (echo 0x1${classid_0x} > /cgroup/net_cls/${dev}${keyId}/net_cls.classid)
    if [ $? -ne 0 ]
    then
        exit 4
    fi

    local pids_list=$(echo $pids | cut -d, -f1- --output-delimiter=" ")
    for pid in $pids_list
    do
      echo $pid > /cgroup/net_cls/${dev}${keyId}/tasks
      if [ $? -ne 0 ]
      then
          exit 3
      fi
    done

  elif [ "$1" == "D" ]; then
    keyId=$3
    rate=$(tc class show dev $dev|grep 'htb 1:'${keyId}' parent'|awk -F' ' '{print $9}')
    ceil=$(tc class show dev $dev|grep 'htb 1:'${keyId}' parent'|awk -F' ' '{print $11}')
    tc class del dev $dev parent 1: classid 1:$keyId htb rate $rate ceil $ceil && cgdelete -g net_cls:${dev}${keyId}
    if [ $? -ne 0 ]
      then
          exit 5
    fi
    
  elif [ "$1" == "U" ]; then
    rate=$3
    ceil=$4
    keyId=$5
    tc class change dev $dev parent 1: classid 1:$keyId htb rate ${rate}kbit ceil ${ceil}kbit
    if [ $? -ne 0 ]
      then
          exit 6
    fi
  fi

}

list_pids_by_keyId() {
  local dev=$1
  local keyId=$2
  local pids_list=

  local pids=$(cat /cgroup/net_cls/$dev$keyId/tasks)
  for pid in $pids
  do
    pids_list=${pids_list}${pid}","
  done
  echo $pids_list
  #return pids_list
}

set_pid_in_bandwidth() {
  local op=$1
  local dev=$2
  local keyId=$3
  local pids=$4

  local pids_list=$(echo $pids | cut -d, -f1- --output-delimiter=" ")
  
  if [ "$op" == "a" ]; then
      for pid in $pids_list
      do
        echo $pid > /cgroup/net_cls/${dev}${keyId}/tasks
        if [ $? -ne 0 ]
        then
          exit 3
        fi
      done
  elif [ "$op" == "d" ]; then
    for pid in $pids_list
    do
      echo $pid > /cgroup/net_cls/tasks
      if [ $? -ne 0 ]
      then
          exit 3
      fi
    done
  fi
  return 0

}



op=""

while getopts 'ADULadln:r:c:k:p:h' OPTION
do
  case $OPTION in
    A) Aflag=1
      op="A"
      ;;
    D) Dflag=1
      op="D"
      ;;
    U) Uflag=1
      op="U"
      ;;
    L) Lflag=1
      op="L"
      ;;
    a) aflag=1
      op="a"
      ;;
    d) dflag=1
      op="d"
      ;;
    l) lflag=1
      op="l"
      ;;
    n) dev="$OPTARG"
      ;;
    r) rate="$OPTARG"
      ;;
    c) ceil="$OPTARG"
      ;;
    k) keyId="$OPTARG"
      ;;
    p) pids="$OPTARG"
      ;;
    h) echo $"Usage : $0 {-A|-D|-U|L|a|d|l|n:dev number|r:rate|c:ceil|k:keyId|p:pids|-h help}"
      exit 2
      ;;
    ?) echo $"Usage : $0 {-A|-D|-U|L|a|d|l|n:dev number|r:rate|c:ceil|k:keyId|p:pids|-h help}"
      exit 2
      ;;
  esac
done


if [ "$Aflag$Dflag$Uflag$Lflag$aflag$dflag$lflag" != "1" ]
then
    exit 2
fi


if [ "$Lflag" == "1" ]; then
  #列举某个网卡上所有的关于进程流控的信息，返回字符串，以逗号分隔
  info=$(list_dev_bandwidth_info $dev)
  echo $info && exit 0
fi

is_keyId_valid $keyId

if [ "$Aflag" == "1" ]; then
  #以外键keyId为主，创建对pid或者pids流控规则
  set_bandwidth_rule $op $dev $rate $ceil $keyId $pids
  if [ $? -ne 0 ]
    then
      exit $?
    fi
fi

if [ "$Dflag" == "1" ]; then
  #以外键keyId为主，删除对pid或者pids流控规则
  set_bandwidth_rule $op $dev $keyId
  if [ $? -ne 0 ]
    then
      exit $?
    fi
fi

if [ "$Uflag" == "1" ]; then
  #以外键keyId为主，更新对pid或者pids流控规则的带宽大小
  set_bandwidth_rule $op $dev $rate $ceil $keyId
  if [ $? -ne 0 ]
    then
      exit $?
    fi
fi

if [ "$lflag" == "1" ]; then
  #列举出keyId下所有的pid（当有进程死掉之后，可以刷新出来最新的pid信息）
  pids_info=$(list_pids_by_keyId $dev $keyId)
  echo $pids_info && exit 0
fi

if [ "$aflag" == "1" ]; then
  #对某一个以keyId为标识的项目中，它可以拥有一个或者多个pid，所以可以针对pid进行追加
  set_pid_in_bandwidth $op $dev $keyId $pids
  if [ $? -ne 0 ]
    then
      exit $?
    fi
fi

if [ "$dflag" == "1" ]; then
  #对某一个以keyId为标识的项目中，它可以拥有一个或者多个pid，所以可以针对pid进行追加
  set_pid_in_bandwidth $op $dev $keyId $pids
  if [ $? -ne 0 ]
    then
      exit $?
    fi
fi

exit 0
