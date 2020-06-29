#!/bin/bash

####common VIRT_TYPE specific value ################
VIRT_TYPE="azure"

cd ..
source ./commonutil.sh

#### VIRT_TYPE specific processing  (must define)###
	RG_NAME="rg-${suffix}"

get_External_IP(){
	expr "$1" + 1 >/dev/null 2>&1
	if [ $? -lt 2 ]
	then
    		NODENAME="$NODEPREFIX"`printf "%.3d" $1`
	else
    		NODENAME=$1
	fi

	ip_name=ip_${NODENAME}
	External_IP=`az vm show -g $RG_NAME -n $NODENAME -d | grep publicIps | awk -F '"' '{print $4}'`
	echo $External_IP	
}

get_Internal_IP(){
	expr "$1" + 1 >/dev/null 2>&1
	if [ $? -lt 2 ]
	then
    		NODENAME="$NODEPREFIX"`printf "%.3d" $1`
	else
    		NODENAME=$1
	fi
	
	nic_name=nic_${NODENAME}
	Internal_IP=`az vm show -g $RG_NAME -n $NODENAME -d | grep privateIps | awk -F '"' '{print $4}'`

	echo $Internal_IP
}

stop(){
	expr "$1" + 1 >/dev/null 2>&1
	if [ $? -lt 2 ]
	then
    		NODENAME="$NODEPREFIX"`printf "%.3d" $1`
	else
    		NODENAME=$1
	fi
	az vm deallocate -g $RG_NAME -n $NODENAME
}

start(){
	expr "$1" + 1 >/dev/null 2>&1
	if [ $? -lt 2 ]
	then
    		NODENAME="$NODEPREFIX"`printf "%.3d" $1`
	else
    		NODENAME=$1
	fi
	az vm start -g $RG_NAME -n $NODENAME
}

source ./common_menu.sh
