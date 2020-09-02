#!/bin/bash

# set default level 1
VALUE_L="1"
# set default color red
VALUE_SIDE="r"

# get args level setting
while getopts l:s: OPT
do
  case $OPT in
    "l" ) FLG_L="TRUE" ; VALUE_L="$OPTARG" ;;
    "s" ) FLG_S="TRUE"  ; VALUE_SIDE="$OPTARG" ;;
  esac
done

# set judge server state "running"
bash judge/test_scripts/set_running.sh localhost:5000

# launch robot control node
roslaunch burger_war sim_robot_run.launch enemy_level:=$VALUE_L side:=$VALUE_SIDE
