# Pretty much word for word from https://github.com/davedelong/time/pull/35
set -o nounset
set -o errexit

readonly MODULE_NAME=CreditCardScanner
readonly FRAMEWORK_NAME=${MODULE_NAME}
readonly FRAMEWORK_PATH=${FRAMEWORK_NAME}.framework
readonly SWIFT_MODULE_PATH=${FRAMEWORK_PATH}/Modules/${MODULE_NAME}.swiftmodule

readonly XCODE_PROJECT=${FRAMEWORK_NAME}.xcodeproj
readonly SYMROOT=build
readonly IOS_PLATFORM=iOS

readonly REPOSITORY_NAME=credit-card-scanner
readonly CARTHAGE_ROOT=Carthage
readonly CARTHAGE_FRAMEWORK=${MODULE_NAME}.framework

function sdk_for_platform() {
    local platform=${1-}
    if [[ -z "${platform}" ]]; then
        echo "${FUNCNAME[0]}:${LINENO}: Missing platform" && exit 2
    fi

    case ${platform} in
    ${IOS_PLATFORM})
        echo "iphoneos"
        ;;
    *)
        echo "${FUNCNAME[0]}:${LINENO}: Unknown plaform ${platform}" && exit 2
        ;;
    esac
}

function simulator_for_platform() {
    local platform=${1-}
    if [[ -z "${platform}" ]]; then
        echo "${FUNCNAME[0]}:${LINENO}: Missing platform" && exit 2
    fi

    case ${platform} in
    ${IOS_PLATFORM})
        echo "iphonesimulator"
        ;;
    *)
        echo "${FUNCNAME[0]}:${LINENO}: Unknown platform ${platform}" && exit 2
        ;;
    esac
}

function build_path_for_product() {
    local product=${1-}
    if [[ -z "${product}" ]]; then
        echo "Cannot generate the buid path for an empty product." && exit 2
    fi

    echo "${SYMROOT}/Release-${product}"
}

function universal_build_path_for_platform() {
    local platform=${1-}
    if [[ -z "${platform}" ]]; then
        echo "${FUNCNAME[0]}:${LINENO}: Missing platform" && exit 2
    fi

    echo "${SYMROOT}/Release-universal-${platform}"
}

function create_universal_framework() {
    local platform=${1-}
    if [[ -z "${platform}" ]]; then
        echo "${FUNCNAME[0]}:${LINENO}: Missing platform" && exit 2
    fi

    local universal_build_path=$(universal_build_path_for_platform ${platform})

    local sdk=$(sdk_for_platform ${platform})
    local main_product_path=$(build_path_for_product ${sdk})

    cp -RL ${main_product_path} ${universal_build_path}

    local simulator_sdk=$(simulator_for_platform ${platform})
    local simulator_product_path=
    if [[ -n "${simulator_sdk}" ]]; then
        simulator_product_path=$(build_path_for_product ${simulator_sdk})

        cp -RL ${simulator_product_path}/${SWIFT_MODULE_PATH}/* \
            ${universal_build_path}/${SWIFT_MODULE_PATH}
    fi

    local all_products_paths=
    for product_path in ${main_product_path} ${simulator_product_path}; do
        all_products_paths="${all_products_paths} ${product_path}/${FRAMEWORK_PATH}/${FRAMEWORK_NAME}"
    done

    lipo -create ${all_products_paths} \
        -output ${universal_build_path}/${FRAMEWORK_PATH}/${FRAMEWORK_NAME}
}

function archive_product() {
    local platform=${1-}
    if [[ -z "${platform}" ]]; then
        echo "${FUNCNAME[0]}:${LINENO}: Missing platform" && exit 2
    fi

    local sdk=$(sdk_for_platform ${platform})
    local xcargs=${2-}
    xcodebuild archive -sdk ${sdk} SYMROOT=${SYMROOT} ${xcargs}

    local simulator_sdk=$(simulator_for_platform ${platform})
    if [[ -n "${simulator_sdk}" ]]; then
        xcodebuild build -sdk ${simulator_sdk} SYMROOT=${SYMROOT} ${xcargs}
    fi
}

function create_carthage_artefacts() {
    local product_build_path=$(universal_build_path_for_platform ${IOS_PLATFORM})
    local carthage_build_path=${CARTHAGE_ROOT}/Build/${IOS_PLATFORM}

    mkdir -p ${carthage_build_path}
    cp -RL ${product_build_path}/${FRAMEWORK_PATH} ${carthage_build_path}

    zip -r -X ${CARTHAGE_FRAMEWORK}.zip ${CARTHAGE_ROOT}
}

function create_universal_frameworks() {
    create_universal_framework ${IOS_PLATFORM}
}

function archive_products() {
    archive_product ${IOS_PLATFORM}
}

function prepare_environment() {
    rm -rf ${SYMROOT}
    rm -rf ${CARTHAGE_ROOT}
    rm -f ${CARTHAGE_FRAMEWORK}.zip
    rm -rf ${XCODE_PROJECT}

    # Pass xcconfig overrides to make product be built as static framework
    swift package generate-xcodeproj --xcconfig-overrides Package.xcconfig
    xcodebuild clean
}

function main() {
    prepare_environment
    archive_products
    create_universal_frameworks
    create_carthage_artefacts
}

main
