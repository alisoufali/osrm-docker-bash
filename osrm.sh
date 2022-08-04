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

    if [ ! -f ${SOURCE_FILE} ]; then
        echo "Error: SOURCE_FILE:${SOURCE_FILE} does not exist."
        usage
        exit 1
    fi

    if [ ! -f ${DESTINATION_FILE} ]; then
        cp --force ${SOURCE_FILE} ${DESTINATION_FILE}
        return 0
    else
        if [ ${SOURCE_FILE} -nt ${DESTINATION_FILE} ]; then
            cp --update --force ${SOURCE_FILE} ${DESTINATION_FILE}
            return 2
        else
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

    if [ ! -d ${DIRECTORY} ]; then
        mkdir -p ${DIRECTORY}
        return 0
    else
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

    PATTERN_LINE=$(grep "OSRM_DOCKER_ID" ${OSRM_CONFIG_FILE})

    if [ "${PATTERN_LINE}" == "" ]; then
        OSRM_DOCKER_ID=""
    else
        OSRM_DOCKER_ID="${PATTERN_LINE:15}"
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


start () {

    usage() {

        echo "Usage: osrm start
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

    shift

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
        IS_DOCKER_UP=$(docker ps | grep "${OSRM_DOCKER_NAME}")
        if [ "${IS_DOCKER_UP}" == "" ]; then
            docker start "${OSRM_DOCKER_ID}"
        fi
        exit 0
    else
        OSRM_DOCKER_ID=$(docker create -t -p ${OSRM_PORT}:5000 -v "${OSRM_DATA_DIR}:/data" ${OSRM_DOCKER_NAME} sh)
        echo "OSRM_DOCKER_ID=${OSRM_DOCKER_ID}" >> ${OSRM_CONFIG_FILE}
        docker start "${OSRM_DOCKER_ID}"
        exit 0
    fi

}


stop() {

    usage() {

        echo "Usage: osrm stop
              Checks if ${OSRM_DOCKER_NAME} docker has started and if so, it stops 
              the docker.

              Exit status:
                0  if OK,
                1  if any error occured"

    }

    shift

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi
    
    docker stop "${OSRM_DOCKER_ID}"

    exit 0

}


clean_data() {

    usage() {

        echo "Usage: osrm clean_data
              Removes all files inside the osrm data directory. 

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    shift 

    rm -rf ${OSRM_DATA_DIR}/{*,.*}

    exit 0
}


extract() {

    usage() {

        echo "Usage: osrm extract [OPTION]... [FILE].osm.pbf
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

    shift

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

    docker exec -i -t ${OSRM_DOCKER_ID} osrm-extract \
        -p /opt/${VEHICLE_TYPE}.lua \
        /data/${OSM_FULL_FILE_NAME}

    exit 0

}


partition() {

    usage() {

        echo "Usage: osrm partition [FILE].osrm
              Parition *.osrm files. 

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    shift

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

    docker exec -i -t ${OSRM_DOCKER_ID} osrm-partition \
        /data/${OSM_FULL_FILE_NAME}

    exit 0

}


customize() {

    usage() {

        echo "Usage: osrm customize [FILE].osrm
              Customize *.osrm files. 

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    shift

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

    docker exec -i -t ${OSRM_DOCKER_ID} osrm-customize \
        /data/${OSM_FULL_FILE_NAME}

    exit 0

}


routed() {

    usage() {

        echo "Usage: osrm routed [FILE].osrm
              Run a routing engine based on given map data (*.osrm files).

              Mandatory arguments to long options are mandatory for short options too.
              -a, --algorithm            The routing algorithm to be used for route creation.
                                         Currently two algorithms are supported:
                                         * Contraction Hierarchies (ch)
                                         * Multi-Level Dijkstra (mld)
                                         The possible values of algorithm are (ch|mld)
                                         Default algorithm is the mld.

            Exit status:
              0  if OK,
              1  if any error occured"

    }

    shift

    __get_osrm_docker_id
    if [ "${OSRM_DOCKER_ID}" == "" ]; then
        __error_no_docker_found
        exit 1
    fi

    PARSED_ARGUMENTS=$(getopt -a -n extract -o a: --long algorithm: -- "$@")
    VALID_ARGUMENTS=$?
    if [ "${VALID_ARGUMENTS}" != "0" ]; then
        usage
        exit 1
    fi

    ROUTING_ALGORITHM="mld"

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

    docker exec -i -t ${OSRM_DOCKER_ID} osrm-routed \
        --algorithm ${ROUTING_ALGORITHM}\
        /data/${OSM_FULL_FILE_NAME}

    exit 0

}


if [ ! -v OSRM_HOME_DIR ]; then
    echo "Error: OSRM_HOME_DIR environment variable is not defined."
    echo "Please define this variable and try again"
else
    OSRM_DATA_DIR="${OSRM_HOME_DIR}/data"
    OSRM_CONFIG_FILE="${OSRM_HOME_DIR}/osrm.config"
    if [ ! -d "${OSRM_DATA_DIR}" ]; then
        __update_directory "${OSRM_DATA_DIR}"
    fi
    if [ ! -a "${OSRM_CONFIG_FILE}" ]; then
        touch "${OSRM_CONFIG_FILE}"
    fi
fi
OSRM_DOCKER_NAME="osrm/osrm-backend"


if [ $# -gt "0" ]; then
    case "${1}" in
        "start")
            start $@
            ;;
        "stop")
            start $@
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
        "routed")
            routed $@
            ;;
    esac
fi
