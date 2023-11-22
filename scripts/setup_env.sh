#!/usr/bin/env bash

export BORDER_ROUTER_NODE=329 # border router
export COAP_SERVER_NODE=328
export GNRC_NETWORKING_NODE=326
export COAP_CLIENT_NODE=327
export SENSOR_NODE=324
export COAP_CLIENT_TEST_NODE=325

# comment this out in production
export COAP_SERVER_IP="2001:660:5307:3107:a4a9:dc28:5c45:38a9"

# https://www.iot-lab.info/legacy/tutorials/understand-ipv6-subnetting-on-the-fit-iot-lab-testbed/index.html
export BORDER_ROUTER_IP=2001:660:5307:3107::1/64
# export BORDER_ROUTER_IP=2001:660:5307:3108::1/64
# export BORDER_ROUTER_IP=2001:660:5307:3109::1/64
# export BORDER_ROUTER_IP=2001:660:5307:3110::1/64

export ARCH=iotlab-m3

# values are from 11-26
export DEFAULT_CHANNEL=23
# export DEFAULT_CHANNEL=13

export ETHOS_BAUDRATE=500000
export TAP_INTERFACE=tap7
# export TAP_INTERFACE=tap4
# export TAP_INTERFACE=tap5
# export TAP_INTERFACE=tap6

# this is seconds
export JOB_WAIT_TIMEOUT=60
export EXPERIMENT_TIME=120

export BORDER_ROUTER_FOLDER_NAME=gnrc_border_router
export BORDER_ROUTER_EXE_NAME=${BORDER_ROUTER_FOLDER_NAME}_gp12
export BORDER_ROUTER_HOME=${SENSE_HOME}/src/network/${BORDER_ROUTER_FOLDER_NAME}

export GNRC_NETWORKING_FOLDER_NAME=gnrc_networking
export GNRC_NETWORKING_EXE_NAME=${GNRC_NETWORKING_FOLDER_NAME}_gp12
export GNRC_NETWORKING_HOME=${SENSE_HOME}/src/network/${GNRC_NETWORKING_FOLDER_NAME}

export COAP_SERVER_FOLDER_NAME=nanocoap_server
export COAP_SERVER_EXE_NAME=${COAP_SERVER_FOLDER_NAME}_gp12
export COAP_SERVER_HOME=${SENSE_HOME}/src/network/${COAP_SERVER_FOLDER_NAME}

export COAP_CLIENT_FOLDER_NAME=gcoap
export COAP_CLIENT_EXE_NAME=${COAP_CLIENT_FOLDER_NAME}_gp12
export COAP_CLIENT_HOME=${SENSE_HOME}/src/network/${COAP_CLIENT_FOLDER_NAME}

export COAP_CLIENT_TEST_FOLDER_NAME=gcoap_test
export COAP_CLIENT_TEST_EXE_NAME=${COAP_CLIENT_TEST_FOLDER_NAME}_gp12
export COAP_CLIENT_TEST_HOME=${SENSE_HOME}/src/network/${COAP_CLIENT_TEST_FOLDER_NAME}

export SENSOR_READ_FOLDER_NAME=sensor-m3-temperature
export SENSOR_READ_EXE_NAME=${SENSOR_READ_FOLDER_NAME}_gp12
export SENSOR_READ_HOME=${SENSE_HOME}/src/sensor/${SENSOR_READ_FOLDER_NAME}

#SENSE_SCRIPTS_HOME="${SENSE_HOME}/${SCRIPTS}"
#SENSE_STOPPERS_HOME="${SENSE_SCRIPTS_HOME}/stoppers"
#SENSE_FIRMWARE_HOME="${HOME}/bin"


create_stopper_script() {
    local script_name=$(basename "$0")
    local stopper_name="${script_name}_stopper.sh"
    local stopper_path="${SENSE_STOPPERS_HOME}/${stopper_name}"

    echo "Creating '${stopper_path}' script"
    echo "# Stopper script generated by ${script_name}" > "${stopper_path}"

    for job_id in "$@"; do
        echo "JOB_STATE=\$(iotlab-experiment wait --timeout 30 --cancel-on-timeout -i ${job_id} --state Running,Finishing,Terminated,Stopped,Error)" >> "${stopper_path}"
        echo "if [ \"\$JOB_STATE\" = '\"Running\"' ]; then" >> "${stopper_path}"
        echo "    echo \"Stopping Job ID ${job_id}\"" >> "${stopper_path}"
        echo "    iotlab-experiment stop -i ${job_id}" >> "${stopper_path}"
        echo "else" >> "${stopper_path}"
        echo "    echo \"Job ID ${job_id} is not in 'Running' state. Current state: \$JOB_STATE\"" >> "${stopper_path}"
        echo "fi" >> "${stopper_path}"
        echo "" >> "${stopper_path}" # Adds a newline for readability
    done
}


submit_border_router_job() {
    local border_router_node="$1"

    local border_router_job_json=$(iotlab-experiment submit -n ${BORDER_ROUTER_EXE_NAME} -d ${EXPERIMENT_TIME} -l grenoble,m3,${border_router_node},${SENSE_FIRMWARE_HOME}/${BORDER_ROUTER_EXE_NAME}.elf)

    # Extract job ID from JSON output
    local border_router_job_id=$(echo $border_router_job_json | jq -r '.id')
  
    echo $border_router_job_id
}


wait_for_job() {
    local n_node_job_id="$1"

    echo "iotlab-experiment wait --timeout ${JOB_WAIT_TIMEOUT} --cancel-on-timeout -i ${n_node_job_id} --state Running"
    iotlab-experiment wait --timeout "${JOB_WAIT_TIMEOUT}" --cancel-on-timeout -i "${n_node_job_id}" --state Running
}

create_tap_interface() {
  local node_id="$1"
  echo "Create tap interface ${TAP_INTERFACE}"
  echo "nib neigh"
  echo "Creating tap interface..."
  sudo ethos_uhcpd.py m3-${node_id} ${TAP_INTERFACE} ${BORDER_ROUTER_IP}
  sleep 5
  echo "Done creating tap interface..."
}

create_tap_interface_bg() {
  local node_id="$1"
  echo "Create tap interface ${TAP_INTERFACE}"
  echo "nib neigh"
  echo "Creating tap interface..."
  sudo ethos_uhcpd.py m3-${node_id} ${TAP_INTERFACE} ${BORDER_ROUTER_IP} &
  sleep 5
  echo "Done creating tap interface..."
}

stop_jobs() {
    for job_id in "$@"; do
        # Check the state of the job
        JOB_STATE=$(iotlab-experiment wait --timeout 30 --cancel-on-timeout -i ${job_id} --state Running,Terminated,Stopped,Error)

        echo "Job ID ${job_id} State: $JOB_STATE"

        # Stop the job only if it is in 'Running' state
        if [ "$JOB_STATE" = '"Running"' ]; then
            echo "Stopping Job ID ${job_id}"
            iotlab-experiment stop -i ${job_id}
        else
            echo "Job ID ${job_id} is not in 'Running' state. Current state: $JOB_STATE"
        fi

        sleep 1
    done
}


build_wireless_firmware() {

    local firmware_source_folder="$1"
    # if is_first_file_newer "${firmware_source_folder}/bin/${ARCH}/core" "${firmware_source_folder}/main.c"; then
    #     echo "No need to build"
    #     return 0  # Exit the function successfully
    # fi

    echo "Build firmware ${firmware_source_folder}"
    echo "make ETHOS_BAUDRATE=${ETHOS_BAUDRATE} DEFAULT_CHANNEL=${DEFAULT_CHANNEL} BOARD=${ARCH} -C ${firmware_source_folder}"
    make ETHOS_BAUDRATE="${ETHOS_BAUDRATE}" DEFAULT_CHANNEL="${DEFAULT_CHANNEL}" BOARD="${ARCH}" -C "${firmware_source_folder}"

    # Capture the exit status of the make command
    local status=$?

    # Optionally, you can echo the status for logging or debugging purposes
    if [ $status -eq 0 ]; then
        echo "Build succeeded"
    else
        echo "Build failed with exit code $status"
    fi

    # Return the exit status
    return $status
}

build_firmware() {
    local firmware_source_folder="$1"
    # if is_first_file_newer "${firmware_source_folder}/bin/${ARCH}/core" "${firmware_source_folder}/main.c"; then
    #     echo "No need to build"
    #     return 0  # Exit the function successfully
    # fi

    echo "Build firmware ${firmware_source_folder}"
    echo "make BOARD=${ARCH} -C ${firmware_source_folder}"
    make BOARD="${ARCH}" -C "${firmware_source_folder}" clean all

    local status=$?

    # Optionally, you can echo the status for logging or debugging purposes
    if [ $status -eq 0 ]; then
        echo "Build succeeded"
    else
        echo "Build failed with exit code $status"
    fi

    # Return the exit status
    return $status
}

is_first_file_newer() {
    local first_file="$1"
    local second_file="$2"

    if [[ ! -e "$first_file" ]] || [[ ! -e "$second_file" ]]; then
        echo "One or both files do not exist."
        echo "$first_file"
        echo "$second_file"
        return 2  # Return 2 for error due to non-existent files
    fi

    local first_file_mod_time=$(stat -c %Y "$first_file")
    local second_file_mod_time=$(stat -c %Y "$second_file")

    if [[ $first_file_mod_time -gt $second_file_mod_time ]]; then
        return 0  # First file is newer
    elif [[ $first_file_mod_time -le $second_file_mod_time ]]; then
        return 1  # First file is equal or older
    fi
}