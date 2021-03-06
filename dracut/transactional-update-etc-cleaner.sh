#!/bin/bash -e
#
# Check for conflicts in etc overlay on first boot after creating new snapshot
#
# Author: Ignaz Forster <iforster@suse.de>
# Copyright (C) 2018 SUSE Linux GmbH
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

TU_FLAGFILE="${NEWROOT}/var/lib/overlay/transactional-update.newsnapshot"

# Import common dracut variables
. /dracut-state.sh 2>/dev/null

warn_on_conflicting_files() {
  local dir="${1:-.}"
  local file
  local basedir="${PREV_ETC_OVERLAY}/${dir}"
  local checkdir="${CURRENT_ETC_OVERLAY}/${dir}"

  echo "Checking for conflicts between ${PREV_ETC_OVERLAY}/${dir} and ${CURRENT_ETC_OVERLAY}/${dir}..."

  pushd "${checkdir}" >/dev/null
  for file in .[^.]* ..?* *; do
    # Filter unexpanded globs of "for" loop
    if [ ! -e "${file}" ]; then
      continue
    fi

    # Check whether a file present in a newer layer is also present in the
    # original layer and has a timestamp from after branching the (first)
    # snapshot.
    if [ -e "${basedir}/${file}" -a "${basedir}/${file}" -nt "${NEW_OVERLAYS[-1]}" ]; then
      echo "WARNING: ${dir}/${file} or its contents changed in both old and new snapshot after snapshot creation!"
    fi

    # Recursively process directories
    if [ -d "${file}" ]; then
      warn_on_conflicting_files "${dir}/${file}"
    fi
  done
  popd >/dev/null
}

if [ -e "${TU_FLAGFILE}" ]; then
  CURRENT_SNAPSHOT_ID="`findmnt /${NEWROOT} | sed -n 's#.*\[/@/\.snapshots/\([[:digit:]]\+\)/snapshot\].*#\1#p'`"
  . "${TU_FLAGFILE}"

  CURRENT_ETC_OVERLAY="${NEWROOT}/var/lib/overlay/${CURRENT_SNAPSHOT_ID}/etc"
  PREV_ETC_OVERLAY="${NEWROOT}/var/lib/overlay/${PREV_SNAPSHOT_ID}/etc"

  if [ "${CURRENT_SNAPSHOT_ID}" = "${EXPECTED_SNAPSHOT_ID}" -a -e "${CURRENT_ETC_OVERLAY}" ]; then
    NEW_OVERLAYS=()
    for option in `findmnt --noheadings --output OPTIONS /${NEWROOT}/etc | tr ',' ' '`; do
      case "${option%=*}" in
        upperdir)
          NEW_OVERLAYS[0]="${option#*=}"
          ;;
        lowerdir)
          # If the previous overlay is not part of the stack just skip
          if [[ $option != *"${PREV_ETC_OVERLAY}"* ]]; then
            NEW_OVERLAYS=()
            break
          fi

          i=1
          for lowerdir in `echo ${option#*=} | tr ':' ' '`; do
            if [ ${lowerdir} = ${PREV_ETC_OVERLAY} ]; then
              break
            fi
            NEW_OVERLAYS[$i]="${lowerdir}"
            ((i++))
          done
          ;;
      esac
    done

    rm "${TU_FLAGFILE}"

    for overlay in "${NEW_OVERLAYS[@]}"; do
      CURRENT_ETC_OVERLAY="${overlay}"
      warn_on_conflicting_files
    done
  fi
fi
