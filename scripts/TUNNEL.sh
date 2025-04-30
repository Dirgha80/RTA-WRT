#!/bin/bash

# Source the include file containing common functions and variables
if [[ ! -f "./scripts/INCLUDE.sh" ]]; then
    echo "ERROR: INCLUDE.sh not found in ./scripts/" >&2
    exit 1
fi

set -o errexit  # Exit on error
set -o nounset  # Exit on unset variables
set -o pipefail # Exit if any command in a pipe fails

. ./scripts/INCLUDE.sh

# Constants
readonly GH_API="https://api.github.com/repos"
readonly IMMORTALWRT_URL="https://downloads.immortalwrt.org/releases/packages-${VEROP}/${ARCH_3}/luci"

# Initialize variables
declare -a openclash_ipk passwall_ipk
openclash_ipk=("luci-app-openclash|${IMMORTALWRT_URL}")
passwall_ipk=("luci-app-passwall|${IMMORTALWRT_URL}")

# Function to get latest release URL from GitHub
get_github_release() {
    local repo="$1"
    local pattern="$2"
    curl -s "${GH_API}/${repo}/releases/latest" | \
    grep "browser_download_url" | \
    grep -oE "https.*${pattern}" | \
    head -n 1
}

# Function to get release URL from GitHub (non-latest)
get_github_release_any() {
    local repo="$1"
    local pattern="$2"
    curl -s "${GH_API}/${repo}/releases" | \
    grep "browser_download_url" | \
    grep -oE "https.*${pattern}" | \
    head -n 1
}

# Determine core file names
determine_core_files() {
    # OpenClash core
    if [[ "${ARCH_3}" == "x86_64" ]]; then
        meta_file="mihomo-linux-${ARCH_1}-compatible"
    else
        meta_file="mihomo-linux-${ARCH_1}"
    fi
    openclash_core=$(get_github_release "MetaCubeX/mihomo" "${meta_file}-v[0-9]+\.[0-9]+\.[0-9]+\.gz")

    # PassWall core
    passwall_core_file_zip="passwall_packages_ipk_${ARCH_3}"
    passwall_core_file_zip_down=$(get_github_release_any "xiaorouji/openwrt-passwall" "${passwall_core_file_zip}.*.zip")

    # Nikki core
    nikki_file_ipk="nikki_${ARCH_3}-openwrt-${VEROP}"
    nikki_file_ipk_down=$(get_github_release_any "rizkikotet-dev/OpenWrt-nikki-Mod" "${nikki_file_ipk}.*.tar.gz")
}

# Function to download and extract package
handle_package() {
    local url="$1"
    local dest="$2"
    local extract_cmd="$3"
    
    log "INFO" "Downloading package from ${url}"
    if ! ariadl "${url}" "${dest}"; then
        error_msg "Failed to download package from ${url}"
        return 1
    fi

    log "INFO" "Extracting package ${dest}"
    if ! eval "${extract_cmd}"; then
        error_msg "Failed to extract package ${dest}"
        return 1
    fi

    return 0
}

# Package setup functions
setup_openclash() {
    log "INFO" "Setting up OpenClash..."
    
    # Download IPK packages
    download_packages openclash_ipk || return 1
    
    # Download and extract core
    handle_package "${openclash_core}" "files/etc/openclash/core/clash_meta.gz" \
        "gzip -d files/etc/openclash/core/clash_meta.gz" || return 1
    
    return 0
}

setup_passwall() {
    log "INFO" "Setting up PassWall..."
    
    # Download IPK packages
    download_packages passwall_ipk || return 1
    
    # Download and extract core
    handle_package "${passwall_core_file_zip_down}" "packages/passwall.zip" \
        "unzip -qq packages/passwall.zip -d packages && rm packages/passwall.zip" || return 1
    
    return 0
}

setup_nikki() {
    log "INFO" "Setting up Nikki..."
    
    # Download and extract core
    handle_package "${nikki_file_ipk_down}" "packages/nikki.tar.gz" \
        "tar -xzf packages/nikki.tar.gz -C packages && rm packages/nikki.tar.gz" || return 1
    
    return 0
}

# Function to remove icons from theme files


# Main function
main() {
    local rc=0
    
    # Determine core files first
    determine_core_files
    
    case "$1" in
        openclash)
            setup_openclash || rc=1
            ;;
        passwall)
            setup_passwall || rc=1
            ;;
        nikki)
            setup_nikki || rc=1
            ;;
        openclash-passwall)
            setup_openclash || rc=1
            setup_passwall || rc=1
            ;;
        nikki-passwall)
            setup_nikki || rc=1
            setup_passwall || rc=1
            ;;
        nikki-openclash)
            setup_nikki || rc=1
            setup_openclash || rc=1
            ;;
        all-tunnel)
            log "INFO" "Installing all tunnel packages"
            setup_openclash || rc=1
            setup_passwall || rc=1
            setup_nikki || rc=1
            ;;
        no-tunnel)
            log "INFO" "Using no tunnel packages"
            ;;
        *)
            log "ERROR" "Invalid option. Usage: $0 {openclash|passwall|nikki|openclash-passwall|nikki-passwall|nikki-openclash|all-tunnel|no-tunnel}"
            exit 1
            ;;
    esac

    if [[ ${rc} -ne 0 ]]; then
        error_msg "One or more package installations failed"
        exit 1
    else
        log "SUCCESS" "Package installation completed successfully"
    fi
}

# Execute main function
main "$@"
