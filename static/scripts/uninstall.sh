#!/usr/bin/env bash

# ------------------------------------------------------------
# Copyright 2022 The KusionStack Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ------------------------------------------------------------

set -o errexit
set -o nounset
set -o pipefail

# Sudo is required to delete binary from KUSION_HOME_DIR
USE_SUDO=${USE_SUDO:-"false"}

# Specified profile
PROFILE=${PROFILE:-""}

# Kusion location
KUSION_HOME_DIR=${KUSION_HOME_DIR:-"$HOME/.kusion"}

# Indicate whether to skip clearing kusion env in detected profile
SKIP_CLEAR_SOURCE_KUSION_ENV=${SKIP_CLEAR_SOURCE_KUSION_ENV:-"false"}

# Source kusion env file content
SOURCE_KUSION_CONTENT='source $HOME/.kusion/.env'
SOURCE_KUSION_ANNOTATION_CONTENT='# Source kusion env file'

info() {
	command printf '\033[1;32mInfo\033[0m: %s\n' "$1" 1>&2
}

warn() {
	command printf '\033[1;33mWarn\033[0m: %s\n' "$1" 1>&2
}

error() {
	command printf '\033[1;31mError\033[0m: %s\n' "$1" 1>&2
}

runAsRoot() {
	local CMD="$*"

	if [ $EUID -ne 0 ] && [ $USE_SUDO = "true" ]; then
		CMD="sudo $CMD"
	fi

	$CMD
}

echoFexists() {
  [ -f "$1" ] && echo "$1"
}

removeInstallationDir() {
    info "Removing kusion installation dir $KUSION_HOME_DIR..."
    runAsRoot rm -rf "$KUSION_HOME_DIR"
    if [ -d "$KUSION_HOME_DIR" ]; then
        error "Removing kusion installation dir failed."
        return 1
    fi
}

clearProfileSource() {
	if [ $SKIP_CLEAR_SOURCE_KUSION_ENV = true ]; then
		info "Skip clearing kusion env in user profile."
		return 0
	fi

    detected_profile=$(detectProfile "$(basename $SHELL)" "$(uname -s)")
    if [ -z "${detected_profile-}" ]; then
        warn "No supported user profile found. Already tried \$PROFILE ($PROFILE), ~/.bashrc, ~/.bash_profile, ~/.zshrc, ~/.profile, and ~/.config/fish/config.fish. Skip clearing kusion env in user profile."
		return 0
    fi

    info "Clearing kusion env in profile $detected_profile..."
	deleteProfileSourceContent "$detected_profile"
}

detectProfile() {
	local shell_name="$1"
	local uname="$2"

	if [ -f "$PROFILE" ]; then
		info "Current profile: $PROFILE"
		return
	fi

	# try to detect the current shell
	case "$shell_name" in
	bash)
		# Shells on macOS default to opening with a login shell, while Linuxes
		# default to a *non*-login shell, so if this is macOS we look for
		# `.bash_profile` first; if it's Linux, we look for `.bashrc` first. The
		# `*` fallthrough covers more than just Linux: it's everything that is not
		# macOS (Darwin). It can be made narrower later if need be.
		case $uname in
		Darwin)
			echoFexists "$HOME/.bash_profile" || echoFexists "$HOME/.bashrc"
			;;
		*)
			echoFexists "$HOME/.bashrc" || echoFexists "$HOME/.bash_profile"
			;;
		esac
		;;
	zsh)
		echo "$HOME/.zshrc"
		;;
	fish)
		echo "$HOME/.config/fish/config.fish"
		;;
	*)
		# Fall back to checking for profile file existence. Once again, the order
		# differs between macOS and everything else.
		local profiles
		case $uname in
		Darwin)
			profiles=(.profile .bash_profile .bashrc .zshrc .config/fish/config.fish)
			;;
		*)
			profiles=(.profile .bashrc .bash_profile .zshrc .config/fish/config.fish)
			;;
		esac

		for profile in "${profiles[@]}"; do
			echoFexists "$HOME/$profile" && break
		done
		;;
	esac
}

deleteProfileSourceContent() {
    local profile="$1"
    local source_line_pattern="^$SOURCE_KUSION_CONTENT$"
	local source_line_annotation_pattern="^$SOURCE_KUSION_ANNOTATION_CONTENT$"

    if grep -qc "$source_line_pattern" "$profile"; then
        line_number=$(grep -n "$source_line_pattern" "$profile" | cut -d: -f1)
        sed -i '' ''"$line_number"'d' "$profile"
    fi
    if grep -q "$source_line_pattern" "$profile"; then
        warn "Failed to delete $SOURCE_KUSION_CONTENT in $profile, please delete it manually."
    else
        info "Delete $SOURCE_KUSION_CONTENT in $profile succeeded."
    fi

	if grep -q "$source_line_annotation_pattern" "$profile"; then
        annotation_line_number=$(grep -n "$source_line_annotation_pattern" "$profile" | cut -d: -f1)
        sed -i '' ''"$annotation_line_number"'d' "$profile"
    fi
}

exit_trap() {
	result=$?
	if [ "$result" != "0" ]; then
        # todo: update to install faq page when determined
		error "Failed to uninstall kusion. Please go to https://kusionstack.io for more support."
	else
		info "Uninstall kusion succeeded. Hope you can use kusion again, visit https://kusionstack.io for more information."
	fi

	exit $result
}

# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
trap "exit_trap" EXIT

removeInstallationDir
clearProfileSource