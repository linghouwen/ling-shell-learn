#!/bin/bash
#andrew ling  2016/09/26

#tool function
netmask_to_subnet() {
  #netmask=255.255.255.0
  netmask=$1
  netmask_list=$(echo $netmask|cut -d. -f1- --output-delimiter=" ")
  sum=0
  for mask in $netmask_list
  do
    if [[ $mask == 0 ]]
    then
      sum=$[$sum+0]
    elif [[ $mask == 128 ]]
    then
      sum=$[$sum+1]
    elif [[ $mask == 192 ]]
    then
      sum=$[$sum+2]
    elif [[ $mask == 224 ]]
    then
      sum=$[$sum+3]
    elif [[ $mask == 240 ]]
    then
      sum=$[$sum+4]
    elif [[ $mask == 248 ]]
    then
      sum=$[$sum+5]
    elif [[ $mask == 252 ]]
    then
      sum=$[$sum+6]
    elif [[ $mask == 254 ]]
    then
      sum=$[$sum+7]
    elif [[ $mask == 255 ]]
    then
      sum=$[$sum+8]
    fi
  done
  return $sum
}

#get the network information, it include:ipaddress,netmask,board cast,gateway
list_network_info() {
  local op=$1
  local nic_name=
  local nics_info=
  local table_name=
  local is_default_gw=
  if [ "$op" == "L" ]; then
    #找到所有的网卡设备
    nics_list=$(ls /sys/class/net/)
    for nic in $nics_list; do
      if [ "$nic" == "lo" ] || [ "$nic" == "bonding_masters" ]; then
        continue
      fi
      slave_info=$(ip addr show $nic|grep SLAVE)
      if [ "$slave_info" != "" ]; then
        continue
      fi
      master_info=$(ip addr show $nic|grep MASTER)
      is_master=
      if [ "$master_info" != "" ]; then
        is_master=0
        slaves=$(cat /proc/net/bonding/$nic|grep 'Slave Interface:'|awk -F' ' '{print $3}')
        nics_info=${nics_info}"interface "${nic}", type MASTER, slaves "${slaves}", "
      fi

      #table_name=net_${nic}
      ipaddress=$(ip addr show $nic |grep inet[^0-9]|awk -F' ' '{print $2}'|awk -F'/' '{print $1}')
      if [ "$ipaddress" != "" ]; then
        #gateway=$(ip route show table $table_name |grep default|awk -F' ' '{print $3}')
        gateway=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic} |grep GATEWAY|awk -F'=' '{print $2}')
        is_default_gw="false"
        is_set_default_gw=$(ip route show|grep default|grep 'default via '${gateway}' dev '${nic}' ')
        if [ "$is_set_default_gw" != "" ]; then
          is_default_gw="true"
        fi

      fi
    
      if [ -f /etc/sysconfig/network-scripts/ifcfg-${nic} ]; then
        netmask=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic} |grep NETMASK|awk -F'=' '{print $2}')
      fi
      if [ "$is_master" == "0" ]; then
        nics_info=${nics_info}"ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}", default_gateway "${is_default_gw}";"
      else
        nics_info=${nics_info}"interface "${nic}", ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}", default_gateway "${is_default_gw}";"
      fi
      
    done
    echo $nics_info

  elif [ "$op" == "l" ]; then
    nic_name=$2

    ipaddress=$(ip addr show $nic_name |grep inet[^0-9]|awk -F' ' '{print $2}'|awk -F'/' '{print $1}')
    if [ "$ipaddress" != "" ]; then
      #gateway=$(ip route show table $table_name |grep default|awk -F' ' '{print $3}')
      gateway=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic_name} |grep GATEWAY|awk -F'=' '{print $2}')
      is_set_default_gw=$(ip route show|grep default|grep 'default via '${gateway}' dev '${nic_name}' ')
      if [ "$is_set_default_gw" != "" ]; then
        is_default_gw="true"
      fi
    fi
    
    if [ -f /etc/sysconfig/network-scripts/ifcfg-${nic_name} ]; then
      netmask=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic_name} |grep NETMASK|awk -F'=' '{print $2}')
    fi

    master_info=$(ip addr show $nic_name|grep MASTER)
    is_master=
    if [ "$master_info" != "" ]; then
      is_master=0
      slaves=$(cat /proc/net/bonding/$nic_name|grep 'Slave Interface:'|awk -F' ' '{print $3}')
      nics_info="interface "${nic_name}", type MASTER, slaves "${slaves}", ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}", default_gateway "${is_default_gw}
    else
      nics_info="interface "${nic_name}", type SLAVE, ipaddress "${ipaddress}", gateway "${gateway}", netmask "${netmask}", default_gateway "${is_default_gw}
    fi
    echo $nics_info
  fi

}

#set the network
set_network() {
  local nic_name=$1
  local ipaddress=$2
  local netmask=$3
  local gateway=$4
  local is_default_gw=$5
  local is_work_right_now=$6
  local dir_path=/etc/sysconfig/network-scripts/

  #如果网卡存在，但配置文件不存在，即创建网卡配置文件，如果网卡不存在，即抛出
  is_nic_exist=$(ip addr show |grep ' '${nic_name}':')
  if [ ! -f ${dir_path}ifcfg-$nic_name ]; then
    if [ "$is_nic_exist" != "" ]; then
      cat > ${dir_path}ifcfg-${nic_name} << EOF
DEVICE=${nic_name}
NAME=${nic_name}
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=no
EOF
    else
      exit 3
    fi
  fi

  #网卡已经被设置bond功能，还没有被释放，不能对该网络接口进行配置
  is_set_bond=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic_name} |grep MASTER=)
  if [ "$is_set_bond" != "" ]; then
    exit 8
  fi

  if [ "$is_work_right_now" == "0" ]; then
    
    #删除旧ipaddress，然后再赋值新ipaddress
    old_netmask=$(tail /etc/sysconfig/network-scripts/ifcfg-${nic_name} |grep NETMASK|awk -F'=' '{print $2}')
    if [ "$old_netmask" != "" ]; then
      netmask_to_subnet $old_netmask
      old_subnet=$?
      old_ipaddress=$(ip addr show $nic_name |grep inet[^0-9]|awk -F' ' '{print $2}'|awk -F'/' '{print $1}')
      if [[ "$old_ipaddress" != "" ]]; then
        ip addr del ${old_ipaddress}/${old_subnet} dev $nic_name
      fi
    fi

    netmask_to_subnet $netmask
    new_subnet=$?
    ip addr add ${ipaddress}/${new_subnet} dev $nic_name

  fi

#将新的网络接口信息放到网络接口配置文件中
cat > ${dir_path}ifcfg-$nic_name << EOF
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
PEERDNS=yes
PEERROUTES=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_PEERDNS=yes
IPV6_PEERROUTES=yes
IPV6_FAILURE_FATAL=no
ONBOOT=yes
NAME=${nic_name}
DEVICE=${nic_name}
IPADDR=${ipaddress}
NETMASK=${netmask}
GATEWAY=${gateway}
EOF

  if [ "$is_default_gw" == "0" ] && [ "$is_work_right_now" == "0" ]; then
    #重启网络
    service network restart
    #先删除默认路由，然后再创建默认路由网关，考虑存在多个默认网卡的出错情况。
    default_gw_list=$(ip route show|grep default|grep -v 'default via '${gateway}' dev '${nic_name}|awk -F' ' '{print $3}')
    for gw in $default_gw_list
    do
      ip route del default
    done
    is_set_default_gw=$(ip route show|grep default|grep 'default via '${gateway}' dev '${nic_name}' ')
    if [ "$is_set_default_gw" == "" ]; then
      ip route add default via $gateway  dev $nic_name
    fi

  fi

  #启动网络 注意这里重启了全部的网络，是否仅启动设置的网卡即可呢？ip link set eth0 upi ？
  if [ "$is_default_gw" != "0" ] && [ "$is_work_right_now" == "0" ]; then
    ip link set $nic_name up
    service network restart
  fi

}

#set the bonds,support different mode.
#先检查bond功能，如果没有bond模块就返回信息提示，如果有bond模块，但是没有设置好初始化
#先设置bond的初始化功能，然后再设置bond。
init_before_bone() {
  systemctl stop NetworkManager
  #check the system is supported the bond or not
  local supported=$(modinfo bonding | grep filename|awk -F' ' '{print $2}')
  if [ "$supported" == "" ]; then
    exit 5
  fi
  return 0
}

set_bond() {
  local dir_path=/etc/sysconfig/network-scripts/
  local bond_name=$1
  local nics_name=$2
  local mode=$3
  local ipaddress=$4
  local netmask=$5
  local gateway=$6
  local is_default_gw=$7
  local is_work_right_now=$8

  bond_info=$(ip addr show |grep ' '${bond_name}':')
  if [ "$bond_info" != "" ]; then
    #判断bond是被配置好的，还是遗留下来的垃圾没有删除干净
    slaves_list=$(cat /etc/modprobe.d/dist.conf |grep 'install '${bond_name}' ')
    if [ "$slaves_list" == "" ]; then
      echo -${bond_name} > /sys/class/net/bonding_masters
    else
      exit 4
    fi
  fi
  #即使bond信息还没有生效，但是如果已经对该bond进行设置了，那么就不能覆盖原先的配置，需要先删除，再配置。
  is_bond_exist=$(cat /etc/modprobe.d/dist.conf |grep 'install '${bond_name}' ')
  if [ "$is_bond_exist" != "" ]; then
    exit 4
  fi

  local nics_list=$(echo $nics_name | cut -d, -f1- --output-delimiter=" ")
  for nic_name in $nics_list
  do
    is_nic_exist=$(ip addr show |grep ' '${nic_name}':')
    if [ ! -f ${dir_path}ifcfg-${nic_name} ] && [ "$is_nic_exist" == "" ]; then
      exit 3
    fi

cat > ${dir_path}ifcfg-${nic_name} << EOF
DEVICE=${nic_name}
NAME=${nic_name}
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=yes
MASTER=${bond_name}
SLAVE=yes
EOF
  done

cat > ${dir_path}ifcfg-${bond_name} << EOF
DEVICE=${bond_name}
NAME=${bond_name}
TYPE=Bond
BONDING_MASTER=yes
IPADDR=${ipaddress}
NETMASK=${netmask}
GATEWAY=${gateway}
PEERDNS=yes
ONBOOT=yes
BOOTPROTO=static
BONDING_OPTS="mode=${mode} miimon=100"
EOF

  if [ "$is_default_gw" == "0" ] && [ "$is_work_right_now" == "0" ]; then
    #重启网络
    service network restart
    #先删除默认路由，然后再创建默认路由网关，考虑存在多个默认网卡的出错情况。
    default_gw_list=$(ip route show|grep default|grep -v 'default via '${gateway}' dev '${bond_name}|awk -F' ' '{print $3}')
    for gw in $default_gw_list
    do
      ip route del default
    done

    is_set_default_gw=$(ip route show|grep default|grep 'default via '${gateway}' dev '${bond_name}' ')
    if [[ "$is_set_default_gw" == "" ]]; then
      ip route add default via $gateway  dev $bond_name
    fi
  fi

  if [ "$is_default_gw" != "0" ] && [ "$is_work_right_now" == "0" ]; then
    service network restart
  fi

  #设置相关的配置文件，以防重启，网络还可以正常使用
  #/etc/rc.d/rc.local和/etc/modprobe.d/dist.conf文件
  chmod +x /etc/rc.d/rc.local
  is_set_rc_profile=$(cat /etc/rc.d/rc.local|grep 'ifenslave '${bond_name}' ')
  if [ "$is_set_rc_profile" == "" ]; then
    echo "ifenslave ${bond_name} ${nics_list}" >> /etc/rc.d/rc.local
  else
    sed -e "/${bond_name} /d"  /etc/rc.d/rc.local > /etc/rc.d/rc.local.tmp
    mv -f /etc/rc.d/rc.local.tmp /etc/rc.d/rc.local
    echo "ifenslave ${bond_name} ${nics_list}" >> /etc/rc.d/rc.local
    chmod +x /etc/rc.d/rc.local
  fi

  if [ ! -f /etc/modprobe.d/dist.conf ]; then
    echo "install ${bond_name} /sbin/modprobe bonding -o ${bond_name} miimon=100 mode=${mode}" >> /etc/modprobe.d/dist.conf
  else
    is_set_dist_profile=$(cat /etc/modprobe.d/dist.conf|grep ${bond_name}' ')
    if [ "$is_set_dist_profile" == "" ]; then
      echo "install ${bond_name} /sbin/modprobe bonding -o ${bond_name} miimon=100 mode=${mode}" >> /etc/modprobe.d/dist.conf
    else
      sed -e "/${bond_name} /d"  /etc/modprobe.d/dist.conf > /etc/modprobe.d/dist.conf.tmp
      mv -f /etc/modprobe.d/dist.conf.tmp /etc/modprobe.d/dist.conf
      echo "install ${bond_name} /sbin/modprobe bonding -o ${bond_name} miimon=100 mode=${mode}" >> /etc/modprobe.d/dist.conf
    fi
  fi

}

disable_bond() {
  bond_name=$1
  is_work_right_now=$2

  bonds_list=$(cat /sys/class/net/bonding_masters)
  is_bond_exist="false"
  for bond in $bonds_list; do
    if [ "$bond_name" == "$bond" ]; then
      
      is_bond_exist="true"
      slaves_list=$(cat /proc/net/bonding/$bond_name|grep 'Slave Interface:'|awk -F' ' '{print $3}')
      for slave in $slaves_list; do
      #清空网络接口配置文件
cat > /etc/sysconfig/network-scripts/ifcfg-${slave} << EOF
DEVICE=${slave}
NAME=${slave}
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=no
EOF
      done
      rm -f /etc/sysconfig/network-scripts/ifcfg-${bond_name}

      #解除bond立刻生效，并且重启网络
      if [ "$is_work_right_now" == "0" ]; then
        echo -${bond_name} > /sys/class/net/bonding_masters
        service network restart
      fi

    fi
  done
  if [ "$is_bond_exist" == "false" ]; then
    if [ -f /etc/sysconfig/network-scripts/ifcfg-${bond_name} ]; then
      
      dev_profile_list=$(ls /etc/sysconfig/network-scripts/ifcfg-*)
      for dev_profile in $dev_profile_list; do
        is_slave_info=$(cat $dev_profile | grep MASTER=${bond_name})
        if [ "$is_slave_info" != "" ]; then
        slave=$(cat $dev_profile | grep DEVICE | awk -F'=' '{print $2}')
        #清空网络接口配置文件
cat > /etc/sysconfig/network-scripts/ifcfg-${slave} << EOF
DEVICE=${slave}
NAME=${slave}
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=no
EOF
        fi
      done
      rm -f /etc/sysconfig/network-scripts/ifcfg-${bond_name}

    else
      exit 7
    fi
  fi

  #清除相关的配置文件
  #/etc/rc.d/rc.local和/etc/modprobe.d/dist.conf文件
  sed -e "/${bond_name} /d"  /etc/rc.d/rc.local > /etc/rc.d/rc.local.tmp
  mv -f /etc/rc.d/rc.local.tmp /etc/rc.d/rc.local
  chmod +x /etc/rc.d/rc.local
  sed -e "/${bond_name} /d"  /etc/modprobe.d/dist.conf > /etc/modprobe.d/dist.conf.tmp
  mv -f /etc/modprobe.d/dist.conf.tmp /etc/modprobe.d/dist.conf

}

enabled_profile() {
  local default_gw=$1
  local dev_name=""
  #重启网络
  service network restart
  #清除bond垃圾信息
  bonds_list=$(ip addr show|grep MASTER|awk -F' ' '{print $2}'|awk -F':' '{print $1}')
  for bond_name in $bonds_list; do
    #判断bond是被配置好的，还是遗留下来的垃圾没有删除干净
    slaves_list=$(cat /etc/modprobe.d/dist.conf |grep 'install '${bond_name}' ')
    if [ "$slaves_list" == "" ]; then
      echo -${bond_name} > /sys/class/net/bonding_masters
    fi
  done

  #处理默认网关参数的合理性
  if [[ "$default_gw" == "" ]]; then
    exit 2
  fi
  dev_profile_list=$(ls /etc/sysconfig/network-scripts/ifcfg-*)
  for dev_profile in $dev_profile_list; do
    is_default_gw_info=$(cat $dev_profile | grep GATEWAY=${default_gw})
    if [ "$is_default_gw_info" != "" ]; then
      dev_name=$(cat $dev_profile | grep DEVICE | awk -F'=' '{print $2}')
    fi
  done

  if [ "$dev_name" == "" ]; then
    exit 6
  fi

  #先删除默认路由，然后再创建默认路由网关，考虑存在多个默认网卡的出错情况。
  default_gw_list=$(ip route show|grep default|grep -v 'default via '${default_gw}' dev '${dev_name}|awk -F' ' '{print $3}')
  for gw in $default_gw_list
  do
    ip route del default
  done

  is_set_default_gw=$(ip route show|grep default|grep 'default via '${default_gw}' dev '${dev_name}' ')
  if [[ "$is_set_default_gw" == "" ]]; then
    ip route add default via $default_gw  dev $dev_name
  fi

}


op=
is_default_gw=1
is_work_right_now=1

while getopts 'Ll:SADUn:i:I:m:g:frd:b:' OPTION
do
  case $OPTION in
    L) Lflag=1
      op="L"
      ;;
    l) nic_name="$OPTARG"
      lflag=1
      op="l"
      ;;
    S) Sflag=1
      ;;
    A) Aflag=1
      ;;
    D) Dflag=1
      ;;
    U) Uflag=1
      ;;
    n) dev="$OPTARG"
      ;;
    i) ipaddress="$OPTARG"
      ;;
    I) nics_name="$OPTARG"
      ;;
    m) netmask="$OPTARG"
      ;;
    g) gateway="$OPTARG"
      ;;
    f) is_default_gw=0
      ;;
    r) is_work_right_now=0
      ;;
    b) bond_name="$OPTARG"
      ;;
    d) mode="$OPTARG"
      ;;
    ?) echo $"Usage : The parameters input error"
      exit 2
      ;;
  esac
done

if [ "$Lflag$lflag$Sflag$Aflag$Dflag$Uflag" != "1" ]
then
    exit 2
fi

if [ "$Lflag" == "1" ]
then
  #list the nic info
  network_info=$(list_network_info $op)
  echo $network_info && exit 0
fi

if [ "$lflag" == "1" ]
then
  #list the nic info
  network_info=$(list_network_info $op $nic_name)
  echo $network_info && exit 0
fi

if [ "$Sflag" == "1" ]
then
  #set the network
  set_network $dev $ipaddress $netmask $gateway $is_default_gw $is_work_right_now
  exit $?
fi

if [ "$Aflag" == "1" ]
then
  init_before_bone
  set_bond $bond_name $nics_name $mode $ipaddress $netmask $gateway $is_default_gw $is_work_right_now
  exit $?
fi

if [ "$Dflag" == "1" ]
then
  disable_bond $bond_name $is_work_right_now
  exit $?
fi

if [ "$Uflag" == "1" ]; then
  enabled_profile $gateway
  exit $?
fi

exit 0