# Usage variable define and assign
total_loop_time=$1
unit_test_time=10
current_time=$(date "+%Y.%m.%d-%H:%M:%S")
result_file="f0m_i2c_stress_log"_$current_time.txt
board_type=-1
fab_type=-1
vr_verndor_type=-1
tmp_type=-1
i2c_retry_time=3
stress_fail_flag=0 

# print message color define
Info='\033[0;32m'
Error='\033[0;31m'
Warning='\033[1;33m'
NoColor='\033[0m'

function help()
{
  printf "${Info}Usage: $1 [loop time]${NoColor}\n"
  exit
}

function log_message() {
  local message="$1"
  printf "${message}\n" | tee >(sed $'s/\033[[][^A-Za-z]*m//g' >> "$result_file")
}

function wrapper()
{
  loop_count=0
  ret=0

  while [[ $loop_count -lt $unit_test_time ]]; do
    # Call function and change i2c bus number to IPMI i2c maste W/R format (x*2+1)
    $1 $((($2 - 1 )* 2 + 1)) $3 $4 $5
    ret=$?
    if [[ $ret -ne 0 ]]; then
      break
    fi
    loop_count=$(($loop_count + 1))
  done
  if [[ $ret -eq 0 ]]; then
    log_message "Bus $2 $6 address $3 Success"
  else
    log_message "${Warning}Bus $2 device address $3 Failed at unit test loop $loop_count${NoColor}"
    stress_fail_flag=1
  fi
  return $ret

}

function i2c_master_read()
{
  bus=$1
  address=$2
  read_len=$3
  register=$4

  loop_cnt=0

  while [[ $loop_cnt -lt $i2c_retry_time ]]; do
    ret=$(pldmtool raw -m 0x0a -d 0x80 0x3f 0x01 0x15 0xa0 0x00 0x18 0x52 $bus $address $read_len $register 2>/dev/null | grep 'Rx:')
    if [[ $? -eq 0 ]]; then
      completion_code=$(echo "$ret" | awk '{print $12}')
      if [[ $completion_code == 00 ]]; then
        # printf "Completion code 00, exiting loop.\n"
        return 0
      fi
    fi
    # printf "grep 'Rx:' failed, retrying... ($((loop_count1 + 1)))\n"
    loop_cnt=$(($loop_cnt + 1))
  done

  # printf "i2c_master_read retry reached max $i2c_retry_time times\n"
  return 1
}

function get_board_type()
{
  ret=$(pldmtool raw -m 0x0a -d 0x80 0x3f 0x01 0x15 0xa0 0x00 0x18 0x52 0x09 0x4c 0x01 0x1A | grep 'Rx:')
  if [[ $? -ne 0 ]]; then
    log_message "${Error}Failed to execute pldmtool command.${NoColor}"
    exit 1
  fi
  completion_code=$(echo "$ret" | awk '{print $12}')
  board_type=$(echo "$ret" | awk '{print $13}')

  if [[ $completion_code != 00 ]]; then
    log_message "${Error}Get board type failed, completion code: ${completion_code}.${NoColor}"
    exit 1
  fi

  case $board_type in
    "00")
      log_message "The board type is EVB Board, board_type: ${board_type}"
      ;;
    "01")
      log_message "The board type is AEGIS Board, board_type: ${board_type}"
      ;;
    *)
      log_message "${Error}Unable to determine board type, received board_type: ${board_type}.${NoColor}"
      exit 1
      ;;
  esac
}

function get_board_rev_id()
{
  ret=$(pldmtool raw -m 0x0a -d 0x80 0x3f 0x01 0x15 0xa0 0x00 0x18 0x52 0x09 0x4c 0x01 0x1B | grep 'Rx:')
  if [[ $? -ne 0 ]]; then
    log_message "${Error}Failed to execute pldmtool command.${NoColor}"
    exit 1
  fi
  completion_code=$(echo "$ret" | awk '{print $12}')
  rev_id=$(echo "$ret" | awk '{print $13}')
  fab_type=$((rev_id + 1))

  if [[ $completion_code != 00 ]]; then
    log_message "${Error}Get board rev id fail, completion code: ${completion_code}.${NoColor}"
    exit 1
  fi

   case $rev_id in
    "00"|"01"|"02"|"03")
      log_message "The board rev id is FAB${fab_type}"
      ;;
    *)
      log_message "${Error}Unable to determine board board rev id, received board_rev_id: ${rev_id}.${NoColor}"
      exit 1
      ;;
  esac
}

function get_vr_vendor_type()
{
  ret=$(pldmtool raw -m 0x0a -d 0x80 0x3f 0x01 0x15 0xa0 0x00 0x18 0x52 0x09 0x4c 0x01 0x1C | grep 'Rx:')
  if [[ $? -ne 0 ]]; then
    log_message "${Error}Failed to execute pldmtool command.${NoColor}"
    exit 1
  fi
  completion_code=$(echo "$ret" | awk '{print $12}')
  vr_verndor_type=$(echo "$ret" | awk '{print $13}')

  if [[ $completion_code != 00 ]]; then
    log_message "${Error}Get vr vendor type fail, completion code: ${completion_code}.${NoColor}"
    exit 1
  fi

  case $vr_verndor_type in
    "00"|"02"|"04")
      log_message "The VR type is MPS, vr_verndor_type: ${vr_verndor_type}"
      ;;
    "01"|"03"|"05")
      log_message "The VR type is RNS, vr_verndor_type: ${vr_verndor_type}"
      ;;
    *)
      log_message "${Error}Unable to determine VR type, received vr_verndor_type: ${vr_verndor_type}.${NoColor}"
      exit 1
      ;;
  esac
}

function get_tmp_type()
{
  ret=$(pldmtool raw -m 0x0a -d 0x80 0x3f 0x01 0x15 0xa0 0x00 0x18 0x52 0x01 0x98 0x01 0xFE | grep 'Rx:')
  if [[ $? -ne 0 ]]; then
    log_message "${Error}Failed to execute pldmtool command.${NoColor}"
    exit 1
  fi
  completion_code=$(echo "$ret" | awk '{print $12}')

  if [[ $completion_code != 00 ]]; then
    tmp_type=2; # EMC1413
    log_message "The TMP type is EMC1413"
  else
    tmp_type=1; # TMP432
    log_message "The TMP type is TMP432" 
  fi
}

if [ $# -ne 1 ];then
help $0
fi

# Script start 

log_message "${Info}=============== F0M Switch Board i2c stress start ===============${NoColor}"
echo "set_sensor_polling set all 0" > /dev/ttyUSB6
sleep 3s
log_message "Stop BIC sensor polling...."

ret=`pldmtool raw -m 0x0a -d 0x80 0x3f 0x01 0x15 0xa0 0x00 0x18 0x52 0x09 0x4c 0x01 0x07 | grep 'Rx:' `
completion_code=`echo $ret | awk '{print $12}'`
is_power_on=`echo $ret | awk '{print $13}'`

if [[ $completion_code != 00 ]]; then
    log_message "${Error}power on fail, completion code: ${completion_code}. ${NoColor}"
    exit
fi

if [[ $is_power_on -gt 80 ]]; then
  log_message "${Error}The system is not power on, please power on the system before stress. ${NoColor}"
  exit
fi

get_board_type
get_board_rev_id
get_vr_vendor_type
get_tmp_type

while [[ $current_loop -lt $total_loop_time ]];do
  log_message "${Info}=============== LOOP: $(($current_loop + 1)) ===============${NoColor}"
  current_loop=$((current_loop + 1))

  #MPS
  if [[ $vr_verndor_type == 00 ]] || [[ $vr_verndor_type == 02 ]] || [[ $vr_verndor_type == 04 ]];then
    # Bus 1
    log_message "============= [Bus 1] ==========="
    wrapper i2c_master_read 1 0x28 0x01 0x00 "AEGIS_UBC_1_TEMP_C"    
    wrapper i2c_master_read 1 0x34 0x01 0x00 "AEGIS_UBC_2_TEMP_C"    
    wrapper i2c_master_read 1 0x92 0x01 0x00 "AEGIS_TOP_INLET_TEMP_C"    
    wrapper i2c_master_read 1 0x94 0x01 0x00 "AEGIS_TOP_OUTLET_TEMP_C"    
    wrapper i2c_master_read 1 0x96 0x01 0x00 "AEGIS_BOT_INLET_TEMP_C"    
    wrapper i2c_master_read 1 0x9E 0x01 0x00 "AEGIS_BOT_OUTLET_TEMP_C"    
    if [[ $tmp_type == 1 ]];then
      wrapper i2c_master_read 1 0x98 0x01 0x00 "AEGIS_ON_DIE_1_TEMP_C"      
      wrapper i2c_master_read 1 0x9A 0x01 0x00 "AEGIS_ON_DIE_3_TEMP_C"      
    else
      wrapper i2c_master_read 1 0xB8 0x01 0x00 "AEGIS_ON_DIE_1_TEMP_C"      
      wrapper i2c_master_read 1 0x38 0x01 0x00 "AEGIS_ON_DIE_3_TEMP_C"      
    fi
    if [[ $board_type == 00 ]];then
      wrapper i2c_master_read 1 0xF6 0x01 0x00 "AEGIS_P3V3_TEMP_C"      
    fi
    if [[ $rev_id -ge 01 ]];then
      wrapper i2c_master_read 1 0x9E 0x01 0x00 "AEGIS_EUSB_REPEATER"
      wrapper i2c_master_read 1 0x12 0x01 0x00 "AEGIS_321M_CLK_CEN"      
      wrapper i2c_master_read 1 0xD0 0x01 0x00 "AEGIS_100M_CLK_CEN"      
      wrapper i2c_master_read 1 0xCE 0x01 0x00 "AEGIS_100M_CLK_BUFFER"      
      wrapper i2c_master_read 1 0xD8 0x01 0x00 "AEGIS_100M_CLK_BUFFER"      
    fi
    # Bus 2
    log_message "============= [Bus 2] ==========="
    wrapper i2c_master_read 2 0x4C 0x01 0x00 "AEGIS_P0V85_PVDD_TEMP_C"   
    wrapper i2c_master_read 2 0xE0 0x01 0x00 "AEGIS_P0V75_PVDD_CH_N_TEMP_C"   
    wrapper i2c_master_read 2 0xE2 0x01 0x00 "AEGIS_P0V75_PVDD_CH_S_TEMP_C"   
    wrapper i2c_master_read 2 0xE6 0x01 0x00 "AEGIS_P0V75_TRVDD_ZONEA_TEMP_C"   
    wrapper i2c_master_read 2 0xEC 0x01 0x00 "AEGIS_P0V75_TRVDD_ZONEB_TEMP_C"  
    wrapper i2c_master_read 2 0xEA 0x01 0x00 "AEGIS_P1V1_VDDC_HBM0_HBM2_HBM4_TEMP_C"  
    # Bus 3
    log_message "============= [Bus 3] ==========="
    wrapper i2c_master_read 3 0xE4 0x01 0x00 "AEGIS_P0V9_TRVDD_ZONEA_TEMP_C"   
    wrapper i2c_master_read 3 0xE8 0x01 0x00 "AEGIS_P0V9_TRVDD_ZONEB_TEMP_C"  
    wrapper i2c_master_read 3 0xEE 0x01 0x00 "AEGIS_P1V1_VDDC_HBM1_HBM3_HBM5_TEMP_C"   
    wrapper i2c_master_read 3 0xF2 0x01 0x00 "AEGIS_VDDA_PCIE_TEMP_C"    
    if [[ $rev_id -ge 01 ]];then
      # Bus 5
      log_message "============= [Bus 5] ==========="
      wrapper i2c_master_read 5 0x4C 0x01 0x00 "AEGIS_CPLD"
      wrapper i2c_master_read 5 0xA0 0x01 0x00 "AEGIS_CPLD"   
    fi
    if [[ $rev_id == 00 ]];then
      # Bus 7
      log_message "============= [Bus 7] ==========="
      wrapper i2c_master_read 7 0x12 0x01 0x00 "AEGIS_321M_CLK_CEN"   
      wrapper i2c_master_read 7 0xD0 0x01 0x00 "AEGIS_100M_CLK_CEN"    
      wrapper i2c_master_read 7 0xCE 0x01 0x00 "AEGIS_100M_CLK_BUFFER"      
      wrapper i2c_master_read 7 0xD8 0x01 0x00 "AEGIS_100M_CLK_BUFFER"      
    fi
    if [[ $rev_id -ge 01 ]];then
      # Bus 12
      log_message "============= [Bus 12] ==========="
      wrapper i2c_master_read 12 0xA0 0x01 0x00 "AEGIS_EEPROM" 
    fi
  fi
  
  #RNS
  if [[ $vr_verndor_type == 01 ]] || [[ $vr_verndor_type == 03 ]] || [[ $vr_verndor_type == 05 ]];then
    # Bus 1
    log_message "============= [Bus 1] ==========="
    wrapper i2c_master_read 1 0x28 0x01 0x00 "AEGIS_UBC_1_TEMP_C"   
    wrapper i2c_master_read 1 0x34 0x01 0x00 "AEGIS_UBC_2_TEMP_C"    
    wrapper i2c_master_read 1 0x92 0x01 0x00 "AEGIS_TOP_INLET_TEMP_C"   
    wrapper i2c_master_read 1 0x94 0x01 0x00 "AEGIS_TOP_OUTLET_TEMP_C"  
    wrapper i2c_master_read 1 0x96 0x01 0x00 "AEGIS_BOT_INLET_TEMP_C"   
    wrapper i2c_master_read 1 0x9E 0x01 0x00 "AEGIS_BOT_OUTLET_TEMP_C"   
    if [[ $tmp_type == 1 ]];then
      wrapper i2c_master_read 1 0x98 0x01 0x00 "AEGIS_ON_DIE_1_TEMP_C"      
      wrapper i2c_master_read 1 0x9A 0x01 0x00 "AEGIS_ON_DIE_3_TEMP_C"     
    else
      wrapper i2c_master_read 1 0xB8 0x01 0x00 "AEGIS_ON_DIE_1_TEMP_C"      
      wrapper i2c_master_read 1 0x38 0x01 0x00 "AEGIS_ON_DIE_3_TEMP_C"     
    fi   
    if [[ $board_type == 00 ]];then
      wrapper i2c_master_read 1 0xC0 0x01 0x00 "AEGIS_P3V3_TEMP_C"     
    fi
    if [[ $rev_id -ge 01 ]];then
      wrapper i2c_master_read 1 0x9E 0x01 0x00 "AEGIS_EUSB_REPEATER"
      wrapper i2c_master_read 1 0x12 0x01 0x00 "AEGIS_321M_CLK_CEN"     
      wrapper i2c_master_read 1 0xD0 0x01 0x00 "AEGIS_100M_CLK_CEN"     
      wrapper i2c_master_read 1 0xCE 0x01 0x00 "AEGIS_100M_CLK_BUFFER"    
      wrapper i2c_master_read 1 0xD8 0x01 0x00 "AEGIS_100M_CLK_BUFFER"      
    fi
    # Bus 2
    log_message "============= [Bus 2] ==========="
    wrapper i2c_master_read 2 0xE4 0x01 0x00 "AEGIS_P0V85_PVDD_TEMP_C"   
    wrapper i2c_master_read 2 0xC0 0x01 0x00 "AEGIS_P0V75_PVDD_CH_N_TEMP_C"  
    wrapper i2c_master_read 2 0xC2 0x01 0x00 "AEGIS_P0V75_PVDD_CH_S_TEMP_C"   
    wrapper i2c_master_read 2 0xC4 0x01 0x00 "AEGIS_P0V75_TRVDD_ZONEA_TEMP_C"   
    wrapper i2c_master_read 2 0xC6 0x01 0x00 "AEGIS_P0V75_TRVDD_ZONEB_TEMP_C"    
    wrapper i2c_master_read 2 0xE8 0x01 0x00 "AEGIS_P1V1_VDDC_HBM0_HBM2_HBM4_TEMP_C"   
    # Bus 3
    log_message "============= [Bus 3] ==========="
    wrapper i2c_master_read 3 0xC0 0x01 0x00 "AEGIS_P0V9_TRVDD_ZONEA_TEMP_C"    
    wrapper i2c_master_read 3 0xC2 0x01 0x00 "AEGIS_P0V9_TRVDD_ZONEB_TEMP_C"   
    wrapper i2c_master_read 3 0xC4 0x01 0x00 "AEGIS_P1V1_VDDC_HBM1_HBM3_HBM5_TEMP_C"    
    wrapper i2c_master_read 3 0xC6 0x01 0x00 "AEGIS_VDDA_PCIE_TEMP_C"  
    if [[ $rev_id -ge 01 ]];then
      # Bus 5
      log_message "============= [Bus 5] ==========="
      wrapper i2c_master_read 5 0x4C 0x01 0x00 "AEGIS_CPLD"
      wrapper i2c_master_read 5 0xA0 0x01 0x00 "AEGIS_CPLD"   
    fi 
    if [[ $rev_id == 00 ]];then
      # Bus 7
      log_message "============= [Bus 7] ==========="
      wrapper i2c_master_read 7 0x12 0x01 0x00 "AEGIS_321M_CLK_CEN"      
      wrapper i2c_master_read 7 0xD0 0x01 0x00 "AEGIS_100M_CLK_CEN"
      wrapper i2c_master_read 7 0xCE 0x01 0x00 "AEGIS_100M_CLK_BUFFER"      
      wrapper i2c_master_read 7 0xD8 0x01 0x00 "AEGIS_100M_CLK_BUFFER"      
    fi
    if [[ $rev_id -ge 01 ]];then
      # Bus 12
      log_message "============= [Bus 12] ==========="
      wrapper i2c_master_read 12 0xA0 0x01 0x00 "AEGIS_EEPROM" 
    fi
  fi

done

echo "set_sensor_polling set all 1" > /dev/ttyUSB6
log_message "Start BIC sensor polling...."
