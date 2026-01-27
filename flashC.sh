# shellcheck disable=SC2148

flash() {
	start=$(date +%s)
	echo "Putting device in bootloader"
	sudo picotool reboot -f -u
	echo "Moving to C dir"
	cd min_c_demo || exit
	echo "Making build dir"
	mkdir build -p
	cd build || exit
	echo "Building cmake step"
	cmake .. -G Ninja
	echo "Building ninja step"
	ninja
	cd ..
	echo "Going back to root dir"
	cd ..
	DEVICE=""
	while [[ -z "$DEVICE" ]]; do
		echo "Looking for device"
		DEVICE=$(lsblk -b -o NAME,SIZE,TYPE,MOUNTPOINTS,FSTYPE -p | awk -v size_bytes="$((134217216))" '$3=="part" && $2==size_bytes {gsub(/^[^a-zA-Z\/]+/, "", $1); print $1; exit}')
		if [[ -z "$DEVICE" ]]; then
			sleep 0.25
		fi
	done
	echo "Device $DEVICE found"
	echo "Making mount point"
	mkdir -p "./mnt"
	echo "Mounting device"
	sudo mount "$DEVICE" "./mnt"
	echo "Moving program"
	sudo cp "min_c_demo/build/RP2350-Touch-AMOLED-1.8.uf2" "./mnt"
	echo "Unmounting"
	sudo umount "$DEVICE"
	echo "Removing mount point"
	sudo rm mnt -rf
	end=$(date +%s)
	runtime=$((end - start))
	echo "Flashed program in $runtime seconds"
}

export -f flash
trap 'sudo umount mnt 2>/dev/null; sudo rm mnt -rf &&  exit' INT TERM

if [[ $* == *--watch* ]]; then
	echo -e "Watching for changes in C / zig files"
	find . -type f | grep -P '^(?!\./\.zig-cache)(?!\./build).*\.(?:[ch]|zig)$' | entr -d bash -c "clear && flash && echo 'Watching for changes in C / zig files'"
else
	flash
fi
