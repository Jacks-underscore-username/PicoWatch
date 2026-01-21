# shellcheck disable=SC2148

flash() {
	start=$(date +%s)
	echo -e "Putting device in bootloader"
	sudo picotool reboot -f -u
	DEVICE=""
	while [[ -z "$DEVICE" ]]; do
		echo -e "Looking for device"
		DEVICE=$(lsblk -b -o NAME,SIZE,TYPE,MOUNTPOINTS,FSTYPE -p | awk -v size_bytes="$((134217216))" '$3=="part" && $2==size_bytes {gsub(/^[^a-zA-Z\/]+/, "", $1); print $1; exit}')
		if [[ -z "$DEVICE" ]]; then
			sleep 0.25
		fi
	done
	echo -e "Device $DEVICE found"
	echo -e "Making mount point"
	mkdir -p "./mnt"
	echo -e "Mounting device"
	sudo mount "$DEVICE" "./mnt"
	echo -e "Making build dir"
	mkdir build -p
	cd build || exit
	echo -e "Building cmake step"
	cmake .. -G Ninja
	echo -e "Building ninja step"
	ninja
	cd ..
	echo -e "Moving program"
	sudo cp "build/RP2350-Touch-AMOLED-1.8.uf2" "./mnt"
	echo -e "Unmounting"
	sudo umount "$DEVICE"
	echo -e "Removing mount point"
	sudo rm mnt -rf
	end=$(date +%s)
	runtime=$((end - start))
	echo -e "Flashed program in $runtime seconds"
}

export -f flash
trap 'sudo umount mnt 2>/dev/null; sudo rm mnt -rf &&  exit' INT TERM

if [[ $* == *--watch* ]]; then
	echo -e "Watching for changes in C / zig files"
	find . -type f | grep -P '^(?!\./\.zig-cache)(?!\./build).*\.(?:[ch]|zig)$' | entr -d bash -c "clear && flash && echo 'Watching for changes in C / zig files'"
else
	flash
fi
