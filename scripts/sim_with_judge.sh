#!/bin/bash
set -e
set -x

# set default your color red
VALUE_SIDE="r"

# get args level setting
while getopts s: OPT
do
  case $OPT in
    "s" ) FLG_S="TUR"  ; VALUE_SIDE="$OPTARG" ;;
  esac
done


# judge
# run judge server and visualize window
gnome-terminal -e "python judge/judgeServer.py"
sleep 1
gnome-terminal -e "python judge/visualizeWindow.py"

# init judge server for sim setting
case $VALUE_SIDE in
    "r" ) bash judge/test_scripts/init_single_play.sh judge/marker_set/sim.csv localhost:5000 you enemy ;;
    "b" ) bash judge/test_scripts/init_single_play.sh judge/marker_set/sim.csv localhost:5000 enemy you ;;
    * ) bash judge/test_scripts/init_single_play.sh judge/marker_set/sim.csv localhost:5000 you enemy ;;
esac


# robot
case $VALUE_SIDE in
    "r" ) roslaunch burger_war setup_sim.launch ;;
    "b" ) roslaunch burger_war setup_sim_blue.launch ;;
    * ) roslaunch burger_war setup_sim.launch ;;
esac

