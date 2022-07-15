#!/bin/env bash
# Adjust the monitor's brightness based on information from the ambient light sensor (ALS)
#
# Tested only on a Macbook Pro 16,1. No idea how well it'll work on other systems.
# I assume no responsibility if this script unleashes gremlins and bricks
# your device. Use at your own risk.
#
# TODO: Add multi-monitor support

# Feel free to changes these as needed
MONITOR=acpi_video0
SENSOR=iio:device0
KBD=apple::kbd_backlight
ADAPTER=ADP1

BACKLIGHT_DIR="/sys/class/backlight/$MONITOR"
BRI_FILE="${BACKLIGHT_DIR}/brightness"
KBD_BACKLIGHT_DIR="/sys/class/leds/$KBD"
KBD_BRI_FILE="${KBD_BACKLIGHT_DIR}/brightness"

MAX_BRI=$(cat "${BACKLIGHT_DIR}/max_brightness")
KBD_MAX_BRI=$(cat "${KBD_BACKLIGHT_DIR}/max_brightness")

PLUG_STATUS_OLD=$(cat /sys/class/power_supply/$ADAPTER/online)


#######################################
# Settings
[ -f /etc/autolight.conf ] && source /etc/autolight.conf
POLLING_PER=${POLLING_PER:-3}
ML_FRAME=${ML_FRAME:-0.01}
MIN_LUX=${MIX_LUX:-1000}
MAX_LUX=${MAX_LUX:-80000}
MIN_BRI=${MIX_BRI:-12}
BRI_THRESHOLD_FRAC=${BRI_THRESHOLD_FRAC:-0.1}
BRI_UNPLUGGED_MODIFIER=${BRI_UNPLUGGED_MODIFIER:-0.8}
DEBUG=${DEBUG:-false}
SETX=${SETX:-false}

$SETX && set -x
if $DEBUG; then
	for i in POLLING_PER ML_FRAME MIN_LUX MAX_LUX MIN_BRI BRI_THRESHOLD_FRAC BRI_UNPLUGGED_MODIFIER DEBUG SETX; do [ -f /etc/autolight.conf ] && cat /etc/autolight.conf | grep "$i" | grep -v "^\#" | sed -z 's~\n~ ~g'; echo ${!i}; done
fi
#$DEBUG && echo $POLLING_PER
## stdbuf -o 1M pee "cat" "cat | cut -d '=' - -f1 | xargs -I R echo \"\$R\""
## tee >(echo ;expr1=$(echo -ne "$(cut -d '=' - -f1)"); for i in $(echo "$expr1"); do echo ${!i}; done) && echo
#######################################
#######################################
# Adjust brightness based on lux value
# GLOBALS:
#   MIN_LUX, MAX_LUX, MIN_BRI, MAX_BRI,
#   BRI_THRESHOLD_FRAC, BRI_UNPLUGGED_MODIFIER,
#   BRI_FILE, PLUG_STATUS_OLD, AMBI_BRI_OLD
# ARGUMENTS:
#   Lux value
# OUTPUTS:
#   Write new brightness to BRI_FILE
# RETURN:
#   0 if print succeeds, non-zero on error
#######################################
if [[ $POLLING_PER == 0 ]]; then
    SENSOR_FREQ=$(cat /sys/bus/iio/devices/$SENSOR/in_illuminance_sampling_frequency)
    POLLING_PER=$(echo "1/$SENSOR_FREQ" | bc)
fi

change-bri() {
	d_from=$1; d_to=$2; k_from=$3; k_to=$4
	length_d=$(echo "$d_from - $d_to" | bc)
	length_k=$(echo "$k_from - $k_to" | bc)
	steps=$(echo "$POLLING_PER / $ML_FRAME / 2" | bc)

	$DEBUG && echo -e "\nlength_d: $length_d\tlength_k: $length_k\tsteps: $steps"
	$SETX && set +x
	$DEBUG && TS1=$(date +%s.%3N)
	for ((step=1; step<=$steps; step++)); do
                d_res=$(echo "($d_to - $d_from) * $step / $steps + $d_from" | bc) && k_res=$(echo "($k_to - $k_from) * $step / $steps + $k_from" | bc)
                echo "$d_res" > "$BRI_FILE" &
		echo "$k_res" > "$KBD_BRI_FILE" &
        done
	$DEBUG && TS2=$(date +%s.%3N)
	$DEBUG && TSALL=$(printf "%.5f" $(echo "($TS2-$TS1)*1000" | bc))
	$SETX && set -x
	$DEBUG && echo "$TSALL ms"
}

change_brightness() {
    lux=$1

    # Ensure the lux value is within range.
    [[ $lux -lt $MIN_LUX ]] && lux=$MIN_LUX
    [[ $lux -gt $MAX_LUX ]] && lux=$MAX_LUX

    # Percentages are in logspace since humans see logarithmically
    ambi_bri_frac=$(echo "(l($lux)-l($MIN_LUX))/(l($MAX_LUX)-l($MIN_LUX))" | bc -l)

	if $DEBUG; then
		luxpr=$(printf "%.5f" $(echo "l($lux)" | bc -l))
		min_luxpr=$(printf "%.5f" $(echo "l($MIN_LUX)" | bc -l))
		max_luxpr=$(printf "%.5f" $(echo "l($MAX_LUX)" | bc -l))
		echo -e "lux: $luxpr\nmin_lux: $min_luxpr\nmax_lux: $max_luxpr\nambi_bri_frac_old: ($luxpr-$min_luxpr)/($max_luxpr-$min_luxpr) $(printf "%.5f" $(echo "(l($lux)-l($MIN_LUX))/(l($MAX_LUX)-l($MIN_LUX))" | bc -l))"
		echo "ambi_bri_frac: $(printf "%.3f" $(echo " $lux / $MAX_LUX" | bc -l))"
	fi

    plug_status=$(cat /sys/class/power_supply/$ADAPTER/online)
    [[ $plug_status -eq 0 ]] && ambi_bri_frac=$(echo "$ambi_bri_frac*$BRI_UNPLUGGED_MODIFIER" | bc -l) || ambi_bri_frac=$(echo "$ambi_bri_frac*1.2" | bc -l)

    ambi_bri_frac_old=$(echo "(l($(cat $BRI_FILE))-l($MIN_BRI))/(l($MAX_BRI)-l($MIN_BRI))" | bc -l)
    frac_diff=$(echo "$ambi_bri_frac-$ambi_bri_frac_old" | bc)

	$DEBUG && echo "frac_diff: $(printf "%.5f" $frac_diff)"
    # Only change the brightness if the threshhold has been reached or if the computer was plugged/unplugged
    (( $(echo "${frac_diff#-} > $BRI_THRESHOLD_FRAC" | bc) )) && change_bri=true || change_bri=false
    [[ $plug_status -ne $PLUG_STATUS_OLD ]] && change_bri=true

    ambi_bri_float=$(echo "$MAX_BRI*$ambi_bri_frac" | bc -l)

	$DEBUG && echo -e "\nambi_bri_float: $(printf "%.5f" $ambi_bri_float)"
    ambi_bri=$(echo "scale=0;($ambi_bri_float+0.5)/1" | bc)

    [[ $ambi_bri -le $MIN_BRI ]] && ambi_bri=$MIN_BRI
    [[ $ambi_bri -ge $MAX_BRI ]] && ambi_bri=$MAX_BRI
	$DEBUG && echo "ambi_bri: $ambi_bri"

	if [[ $plug_status -eq 0 ]]; then
		kbd_bri_float=$(echo "(1-$ambi_bri_frac/$BRI_UNPLUGGED_MODIFIER)*$KBD_MAX_BRI*$BRI_UNPLUGGED_MODIFIER/2" | bc -l)
		$DEBUG && echo -e "\ncoef: (1-($(printf "%.0f" $ambi_bri_frac)/$BRI_UNPLUGGED_MODIFIER)*$BRI_UNPLUGGED_MODIFIER/2 $(printf "%.5f" $(echo "(1-$ambi_bri_frac/$BRI_UNPLUGGED_MODIFIER)*$BRI_UNPLUGGED_MODIFIER/2" | bc -l))\nkbd_bri: $(printf "%.5f" $kbd_bri_float)"
	else
		kbd_bri_float=$(echo "(1-$ambi_bri_frac/1.2)*$KBD_MAX_BRI" | bc -l)
		$DEBUG && echo -e "\ncoef: (1-$(printf "%.5f" $ambi_bri_frac))/1.2 $(printf "%.5f" $(echo "(1-$ambi_bri_frac/1.2)" | bc -l))\nkbd_bri: $(printf "%.5f" $kbd_bri_float)"
	fi
	kbd_bri=$(printf "%.0f" $kbd_bri_float)
	$DEBUG && echo "kbd_bri: $kbd_bri"
	[ "$kbd_bri" -ne "$(cat $KBD_BRI_FILE)" ] && change_bri=true
	$change_bri && change-bri $(cat $BRI_FILE) $ambi_bri $(cat $KBD_BRI_FILE) $kbd_bri &

    PLUG_STATUS_OLD=$plug_status
}

while true; do
	grep -q closed /proc/acpi/button/lid/LID0/state && continue
	lux=$(cat /sys/bus/iio/devices/$SENSOR/in_illuminance_input)
	change_brightness "$lux"
	sleep $POLLING_PER
done
