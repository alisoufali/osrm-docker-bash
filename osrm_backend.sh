#!/usr/bin/env bash


__update_file() {

    usage() {

        echo "Usage: __update_file [OPTIONS] ... SOURCE_FILE DESTINATION_FILE
              Check if DESTINATION_FILE exists or is older than SOURCE_FILE and
              if so, the SOURCE_FILE will be copied into DESTINATION_FILE.

              Exit status:
                0  if copy was done successfully,
                1  if erro has occurred because source file does not exist,
                2  if copy was done successfully with replacement,
                3  if copy did not happen because the two files were identical,"

    }

    SOURCE_FILE=$1
    DESTINATION_FILE=$2

    echo "Updating ${DESTINATION_FILE} with ${SOURCE_FILE}."

    if [ ! -f ${SOURCE_FILE} ]; then
        echo "Error: SOURCE_FILE:${SOURCE_FILE} does not exist."
        usage
        exit 1
    fi

    if [ ! -f ${DESTINATION_FILE} ]; then
        echo "${DESTINATION_FILE} does not exist. Just doing a normal copy ..."
        cp --force ${SOURCE_FILE} ${DESTINATION_FILE}
        echo "Done"
        return 0
    else
        echo "${DESTINATION_FILE} exists. Checking for replacement ..."
        if [ ${SOURCE_FILE} -nt ${DESTINATION_FILE} ]; then
            echo "${DESTINATION_FILE} is older than ${SOURCE_FILE}. Just doing a replacement."
            cp --update --force ${SOURCE_FILE} ${DESTINATION_FILE}
            echo "Done."
            return 2
        else
            echo "${DESTINATION_FILE} and ${SOURCE_FILE} are the same. No replacement occured."
            return 3
        fi
    fi

}


__update_directory() {

    usage() {

        echo "Usage: __update_directory [OPTIONS] ... DIRECTORY
              Check if directory exists and if not, it will be
              created alongside with its parents

              Exit status:
                0  if directory update was done successfully,
                1  if directory update did not proceed as it existed"

    }

    DIRECTORY=$1

    echo "Creating ${DIRECTORY}. Checking if it exists ..."

    if [ ! -d ${DIRECTORY} ]; then
        echo "${DIRECTORY} does not exist. Creating ${DIRECTORY} ... "
        mkdir -p ${DIRECTORY}
        echo "Done."
        return 0
    else
        echo "${DIRECTORY} exists. There is no need for creation."
        return 1
    fi

}


__get_osrm_docker_id() {

    usage() {

        echo "Usage: __get_osrm_docker_id
              Check if OSRM_DOCKER_ID is defined in OSRM_CONFIG_FILE and if so it gets it.

              Exit status:
                0  if OK,
                1  if any error occured,"

    }

    echo "Getting OSRM-BACKEND Docker ID. Checking ${OSRM_CONFIG_FILE} for OSRM-BACKEND Docker ID ..."

    PATTERN_LINE=$(grep "OSRM_DOCKER_ID" ${OSRM_CONFIG_FILE})

    if [ "${PATTERN_LINE}" == "" ]; then
        OSRM_DOCKER_ID=""
        echo "Could not find OSRM-BACKEND Docker ID."
    else
        OSRM_DOCKER_ID="${PATTERN_LINE:15}"
        echo "OSRM-BACKEND Docker ID found. It is ${OSRM_DOCKER_ID}"
    fi

    return 0

}


__error_no_docker_found() {

    usage() {

        echo "Usage: __error_no_docker_found
              Raises error because docker id is not available in OSRM_CONFIG_FILE."

    }

    echo "Error: There is no osrm docker available to work with"
    echo "Please start osrm docker first by executing command:"
    echo "      osrm start"

}


start() {

    usage() {

        echo "Usage: osrm_backend start
              Checks if osrm/osrm-backend docker has not started yet and if not, it starts 
              the docker and stores it's id as an environment variable.

              Mandatory arguments to long options are mandatory for short options too.
              -p, --port                 The port of the local host to be mapped into port
                                         5000 of the ${OSRM_DOCKER_NAME} container (where it
                                         communicate with local host).
                                         The default local host port is 5000

              Exit status:
                0  if OK,
                1  if any error occured"

    }

    echo "Starting OSRM-BACKEND container."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    PARSED_ARGUMENTS=$(getopt -a -n start -o p: --long port: -- "$@")
    VALID_ARGUMENTS=$?
    if [ "${VALID_ARGUMENTS}" != "0" ]; then
        usage
        exit 1
    fi

    OSRM_PORT="5000"

    eval set -- "${PARSED_ARGUMENTS}"
    while :
    do
        case "${1}" in
            -p | --port)
                OSRM_PORT="${2}"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Error: Invalid argument is passed to function."
                usage
                exit 1
                ;;
        esac
    done

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" != "" ]; then
        echo "Checking if OSRM-BACKEND container with ID = ${OSRM_DOCKER_ID:0:12} is up and running ..."
        IS_DOCKER_UP=$(docker ps | grep "${OSRM_DOCKER_NAME}")
        if [ "${IS_DOCKER_UP}" == "" ]; then
            echo "OSRM-BACKEND container is not running. Starting it up ..."
            docker start "${OSRM_DOCKER_ID}"
            echo "Done."
        else
            echo "${OSRM_DOCKER_NAME} is already up and running with ID = ${OSRM_DOCKER_ID:0:12}."
            echo "You may want to proceed further."
        fi
        exit 0
    else
        echo "Creating OSRM-BACKEND container on local host port = ${OSRM_PORT}"
        OSRM_DOCKER_ID=$(docker create -t -p ${OSRM_PORT}:5000 -v "${OSRM_DATA_DIR}:/data" ${OSRM_DOCKER_NAME} sh)
        echo "Done."
        echo "Writting OSRM_DOCKER_ID in ${OSRM_CONFIG_FILE} ..."
        echo "OSRM_DOCKER_ID=${OSRM_DOCKER_ID}" >> ${OSRM_CONFIG_FILE}
        echo "Done."
        echo "Starting OSRM-BACKEND container ..."
        docker start "${OSRM_DOCKER_ID}"
        echo "Done."
        exit 0
    fi

}


stop() {

    usage() {

        echo "Usage: osrm_backend stop
              Checks if ${OSRM_DOCKER_NAME} docker has started and if so, it stops 
              the docker.

              Exit status:
                0  if OK,
                1  if any error occured"

    }

    echo "Stopping OSRM-BACKEND container."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi
    
    echo "Stopping OSRM-BACKEND container ..."
    docker stop "${OSRM_DOCKER_ID}"
    echo "Done."

    exit 0

}


clean_data() {

    usage() {

        echo "Usage: osrm_backend clean_data
              Removes all files inside the osrm data directory. 

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    echo "Cleaning OSRM-BACKEND data directory: ${OSRM_DATA_DIR}."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    if [ -v OSRM_DATA_DIR ] && [ "${OSRM_DATA_DIR}" != "" ]; then
        echo "Removing all files in ${OSRM_DATA_DIR} ..."
        rm -r ${OSRM_DATA_DIR}/*
        echo "Done."
    fi

    exit 0
}


extract() {

    usage() {

        echo "Usage: osrm_backend extract [OPTION]... [FILE].osm.pbf
              Extract and convert *.osm.pbf file into *.osrm files. 

              Mandatory arguments to long options are mandatory for short options too.
              -v, --vehicle              The name of the vehicle to be used. currently
                                         the vehicles which are supported are car, foot 
                                         and bicycle. if vehicle type is not provided, 
                                         the car is used.

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    echo "Extracting given *.osm.pbf file to compatible *.osrm files."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi

    PARSED_ARGUMENTS=$(getopt -a -n extract -o v: --long vehicle: -- "$@")
    VALID_ARGUMENTS=$?
    if [ "${VALID_ARGUMENTS}" != "0" ]; then
        usage
        exit 1
    fi

    VEHICLE_TYPE="car"

    eval set -- "${PARSED_ARGUMENTS}"
    while :
    do
        case "${1}" in
            -v | --vehicle)
                VEHICLE_TYPE="${2}"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Error: Invalid argument is passed to function."
                usage
                exit 1
                ;;
        esac
    done

    OSM_FULL_FILE_NAME=$1
    if [ "${OSM_FULL_FILE_NAME#*.}" != "osm.pbf" ]; then
        echo "Error: Invalid file provided."
        echo "Please provide a *.osm.pbf file"
        usage
        exit 1
    fi

    __update_file ${PWD}/${OSM_FULL_FILE_NAME} ${OSRM_DATA_DIR}/${OSM_FULL_FILE_NAME}

    echo "Extracting File: ${OSM_FULL_FILE_NAME} with ${VEHICLE_TYPE} ..."
    docker exec -i -t ${OSRM_DOCKER_ID} osrm-extract \
        -p /opt/${VEHICLE_TYPE}.lua \
        /data/${OSM_FULL_FILE_NAME}
    echo "Done."

    exit 0

}


partition() {

    usage() {

        echo "Usage: osrm_backend partition [FILE].osrm
              Parition *.osrm files. 

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    echo "Partitionning given *.osrm.pbf files."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi

    OSRM_FULL_FILE_NAME=$1
    echo ${OSRM_FULL_FILE_NAME}
    if [ "${OSRM_FULL_FILE_NAME#*.}" != "osrm" ]; then
        echo "Error: Invalid file provided."
        echo "Please provide a *.osrm file"
        usage
        exit 1
    fi

    echo "Partitionning File:${OSRM_FULL_FILE_NAME} ..."
    docker exec -i -t ${OSRM_DOCKER_ID} osrm-partition \
        /data/${OSRM_FULL_FILE_NAME}
    echo "Done."

    exit 0

}


customize() {

    usage() {

        echo "Usage: osrm_backend customize [FILE].osrm
              Customize *.osrm files. 

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    echo "Customizing given *.osrm.pbf files."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi

    OSRM_FULL_FILE_NAME=$1
    if [ "${OSRM_FULL_FILE_NAME#*.}" != "osrm" ]; then
        echo "Error: Invalid file provided."
        echo "Please provide a *.osrm file"
        usage
        exit 1
    fi

    echo "Customizing File:${OSRM_FULL_FILE_NAME} ..."
    docker exec -i -t ${OSRM_DOCKER_ID} osrm-customize \
        /data/${OSRM_FULL_FILE_NAME}
    echo "Done."

    exit 0

}


preprocess() {

    usage() {

        echo "Usage: osrm_backend preprocess [OPTION]... [FILE].osm.pbf
              This function preprocess *.osm.pbf files in the following steps:
              1. Extraction and conversion of *.osm.pbf file into *.osrm files using
                 'osrm_backend extract'
              2. Get partitions in *.osrm files using 'osrm_backend partition'
              3. Customize *.osrm files 'osrm_backend customize' 

              Mandatory arguments to long options are mandatory for short options too.
              -v, --vehicle              The name of the vehicle to be used. currently
                                         the vehicles which are supported are car, foot 
                                         and bicycle. if vehicle type is not provided, 
                                         the car is used.

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    echo "Extracting given *.osm.pbf file to compatible *.osrm files."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    RUN_MODE="INDIRECT"

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi

    OSM_FULL_FILE_NAME=$1

    if [ "${OSM_FULL_FILE_NAME#*.}" != "osm.pbf" ]; then
        echo "Error: Invalid file provided."
        echo "Please provide a *.osm.pbf file"
        usage
        exit 1
    fi
    FILE_NAME="${OSM_FULL_FILE_NAME%%.*}"

    PARSED_ARGUMENTS=$(getopt -a -n extract -o v: --long vehicle: -- "$@")
    VALID_ARGUMENTS=$?
    if [ "${VALID_ARGUMENTS}" != "0" ]; then
        usage
        exit 1
    fi

    VEHICLE_TYPE="car"

    eval set -- "${PARSED_ARGUMENTS}"
    while :
    do
        case "${1}" in
            -v | --vehicle)
                VEHICLE_TYPE="${2}"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Error: Invalid argument is passed to function."
                usage
                exit 1
                ;;
        esac
    done

    echo "Begining file preprocessing ..."
    extract -v "${VEHICLE_TYPE}" "${FILE_NAME}.osm.pbf"
    partition "${FILE_NAME}.osrm"
    customize "${FILE_NAME}.osrm"
    echo "Done."

}


routed() {

    usage() {

        echo "Usage: osrm_backend routed [FILE].osrm
              Run a routing engine based on given map data (*.osrm files).

              Mandatory arguments to long options are mandatory for short options too.
              -a, --algorithm             The routing algorithm to be used for route creation.
                                          Currently two algorithms are supported:
                                          * Contraction Hierarchies (ch)
                                          * Multi-Level Dijkstra (mld)
                                          The possible values of algorithm are (ch|mld)
                                          Default algorithm is the mld.
              --max-alternatives          Maximum alternative routes the program will check for
                                          each pair of coordinates. The default value is 3000
              --max-matching-size         Maximum value of matching size. The default value is 
                                          100000
              --max-nearest-size          Maximum value of nearest size. The default value is
                                          100000
              --max-table-size            Maximum value of table size. The default value is
                                          100000
              --max-trip-size             Maximum value of trip size. The default value is
                                          100000
              --max-viaroute-size         Maximum value of viaroute size. The default value is
                                          100000
              

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    echo "Starting Routing engine."

    if [ "${RUN_MODE}" == "DIRECT" ]; then
        shift
    fi

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi

    PARSED_ARGUMENTS=$(getopt -a -n routed -o a: --long algorithm:,max-alternatives:,max-matching-size:,--max-nearest-size:,--max-table-size:,--max-trip-size:--max-viaroute-size -- "$@")
    VALID_ARGUMENTS=$?
    if [ "${VALID_ARGUMENTS}" != "0" ]; then
        usage
        exit 1
    fi

    ROUTING_ALGORITHM="mld"
    MAX_ALTERNATIVES="3000"
    MAX_MATCHING_SIZE="100000"
    MAX_NEAREST_SIZE="100000"
    MAX_TABLE_SIZE="100000"
    MAX_TRIP_SIZE="100000"
    MAX_VIAROUTE_SIZE="100000"

    eval set -- "${PARSED_ARGUMENTS}"
    while :
    do
        case "${1}" in
            -a | --algorithm)
                case "${2}" in
                    "mld")
                        ROUTING_ALGORITHM="mld"
                        ;;
                    "ch")
                        ROUTING_ALGORITHM="ch"
                        ;;
                    *)
                        echo "Error: Invalid algorithm is provided."
                        usage
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --max-alternatives)
                MAX_ALTERNATIVES="${2}"
                shift 2
                ;;
            --max-matching-size)
                MAX_MATCHING_SIZE="${2}"
                shift 2
                ;;
            --max-nearest-size)
                MAX_NEAREST_SIZE="${2}"
                shift 2
                ;;
            --max-table-size)
                MAX_TABLE_SIZE="${2}"
                shift 2
                ;;
            --max-trip-size)
                MAX_TRIP_SIZE="${2}"
                shift 2
                ;;
            --max-viaroute-size)
                MAX_VIAROUTE_SIZE="${2}"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Error: Invalid argument is passed to function."
                usage
                exit 1
                ;;
        esac
    done

    OSRM_FULL_FILE_NAME=$1
    if [ "${OSRM_FULL_FILE_NAME#*.}" != "osrm" ]; then
        echo "Error: Invalid file provided."
        echo "Please provide a *.osrm file"
        usage
        exit 1
    fi

    echo "Starting routing engine with max-alternatives = ${MAX_ALTERNATIVES}, max-matching-size = ${MAX_MATCHING_SIZE}, max-nearest-size = ${MAX_NEAREST_SIZE}, max-table-size = ${MAX_TABLE_SIZE}, max-trip-size = ${MAX_TRIP_SIZE}, max-viaroute-size = ${MAX_VIAROUTE_SIZE} and finally algorithm = ${ROUTING_ALGORITHM} ..."
    docker exec -i -t ${OSRM_DOCKER_ID} osrm-routed \
        --max-alternatives ${MAX_ALTERNATIVES} \
        --max-matching-size ${MAX_MATCHING_SIZE} \
        --max-nearest-size ${MAX_NEAREST_SIZE} \
        --max-table-size ${MAX_TABLE_SIZE} \
        --max-trip-size ${MAX_TRIP_SIZE} \
        --max-viaroute-size ${MAX_VIAROUTE_SIZE} \
        --algorithm ${ROUTING_ALGORITHM}\
        /data/${OSRM_FULL_FILE_NAME}
    echo "Done."

    exit 0

}


if [ ! -v OSRM_HOME_DIR ] || [ "${OSRM_HOME_DIR}" == "" ]; then
    echo "Error: OSRM_HOME_DIR environment variable is not defined."
    echo "Please define this variable and try again"
    exit 1
else
    echo "Using ${OSRM_HOME_DIR} as OSRM-BACKEND home directory."
    OSRM_DATA_DIR="${OSRM_HOME_DIR}/data"
    echo "Using ${OSRM_DATA_DIR} as OSRM-BACKEND data directory."
    OSRM_CONFIG_FILE="${OSRM_HOME_DIR}/osrm.config"
    echo "Using ${OSRM_CONFIG_FILE} as OSRM-BACKEND cinfig file."
    if [ ! -d "${OSRM_DATA_DIR}" ]; then
        __update_directory "${OSRM_DATA_DIR}"
        echo "Done."
    fi
    if [ ! -a "${OSRM_CONFIG_FILE}" ]; then
        echo "${OSRM_CONFIG_FILE} does not exist, creating one ..."
        touch "${OSRM_CONFIG_FILE}"
        echo "Done."
    fi
fi
OSRM_DOCKER_NAME="osrm/osrm-backend"
RUN_MODE="DIRECT"


if [ $# -gt "0" ]; then
    case "${1}" in
        "start")
            start $@
            ;;
        "stop")
            stop $@
            ;;
        "clean_data")
            clean_data $@
            ;;
        "extract")
            extract $@
            ;;
        "partition")
            partition $@
            ;;
        "customize")
            customize $@
            ;;
        "preprocess")
            preprocess $@
            ;;
        "routed")
            routed $@
            ;;
    esac
fi
