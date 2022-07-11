#!/usr/bin/env bash
#set -x

intel_dir=/sys/class/backlight/acpi_video0
kbd_dir=/sys/class/leds/apple::kbd_backlight

power_file=/sys/class/power_supply/ADP1/online
screen_file=$intel_dir/brightness
kbd_file=$kbd_dir/brightness
lid_file=/proc/acpi/button/lid/LID0/state
light_file="/sys/bus/iio/devices/iio:device0/in_intensity_both_input"
#/sys/devices/platform/applesmc.768/light"

#####################################################
# wait drivers loaded

$ML_DEBUG && echo checking $intel_dir and $kbd_dir...
while [ ! -d $intel_dir -o ! -d $kbd_dir ]; do
    sleep 1
done
screen_max=$(cat $intel_dir/max_brightness)
kbd_max=$(cat $kbd_dir/max_brightness)

#####################################################
# Settings
[ -f /etc/macbook-lighter.conf ] && source /etc/macbook-lighter.conf
ML_DURATION=${ML_DURATION:-1.5}
ML_FRAME=${ML_FRAME:-0.02}
ML_INTERVAL=${ML_INTERVAL:-3}
ML_BRIGHT_ENOUGH=${ML_BRIGHT_ENOUGH:-80000}
ML_SCREEN_THRESHOLD=${ML_SCREEN_THRESHOLD:-5}
ML_SCREEN_MIN_BRIGHT=${ML_SCREEN_MIN_BRIGHT:-12}
ML_KBD_BRIGHT=${ML_KBD_BRIGHT:-60}
ML_BATTERY_DIM=${ML_BATTERY_DIM:-0.2}
ML_AUTO_KBD=${ML_AUTO_KBD:-true}
ML_AUTO_SCREEN=${ML_AUTO_SCREEN:-true}
ML_DEBUG=${ML_DEBUG:-false}

#####################################################
# Private States
screen_ajusted_at=0
kbd_ajusted_at=0

function get_light {
    val=$(cat $light_file)   # eg. (41,0)
#   val=${val:1:-3}    # eg. 41
    val=$(($val > $ML_BRIGHT_ENOUGH ? $ML_BRIGHT_ENOUGH : $val))
    val=$(($val == 0 ? 1 : $val))
    echo $val
}

function transition {
    from=$1
    to=$2
    dev=$3
    $ML_DEBUG && echo "transition $dev from $from to $to"
    length=$(echo "$from - $to" | bc)
    steps=$(echo "$ML_DURATION / $ML_FRAME" | bc)
                $ML_DEBUG && echo "----- length: $length ; ML_DURATION: $ML_DURATION ML_FRAME: $ML_FRAME ; steps: $steps" && echo
    for ((step=1; step<=$steps; step++)); do
        result=$(echo "($to - $from) * $step / $steps + $from" | bc)
        echo "$result" > "$dev"
    done
}

function screen_range {
    screen_to=$1
    if (( screen_to < ML_SCREEN_MIN_BRIGHT )); then
        echo $ML_SCREEN_MIN_BRIGHT
    elif (( screen_to > screen_max )); then
        echo $screen_max
    else
        echo $screen_to
    fi
}

function kbd_range {
    kbd_to=$1
        if (( screen_to <= ML_SCREEN_MIN_BRIGHT )); then
                echo $kbd_max
        elif (( screen_to >= screen_max )); then
                echo 0
        else
    if (( kbd_to <= 0 )); then
        echo 0
    elif (( kbd_to >= kbd_max )); then
        echo $kbd_max
    else
        echo $kbd_to
    fi
        fi
}

function update_screen {
    light=$1
    screen_from=$(cat $screen_file)
#    screen_to=$(echo "$screen_from * $light / $screen_ajusted_at" | bc)
    screen_to=$(echo "1.4 * $coef * $screen_max * $light / $ML_BRIGHT_ENOUGH" | bc)
    screen_to=$(screen_range $screen_to)
    if (( screen_to - screen_from > -ML_SCREEN_THRESHOLD && screen_to - screen_from < ML_SCREEN_THRESHOLD )); then
        $ML_DEBUG && echo "screen threshold not reached($screen_from->$screen_to), skip update" && echo
        return
    fi
$ML_DEBUG && echo light:$light, screen_ajusted_at:$screen_ajusted_at, screen_brt: $(cat $screen_file)
    screen_ajusted_at=$light
    transition $screen_from $screen_to $screen_file
}

function update_kbd {
    light=$1
    kbd_from=$(cat $kbd_file)
    $ML_DEBUG &&  echo -n "kbd_from: $kbd_from "
#    if (( kbd_from != 0 )); then
#        ML_KBD_BRIGHT=$kbd_from
#    fi

# Old
#    if (( light >= ML_BRIGHT_ENOUGH && kbd_ajusted_at < ML_BRIGHT_ENOUGH )); then
    if (( light >= ML_BRIGHT_ENOUGH )); then
        kbd_to=0
# Old
#    elif (( light < ML_BRIGHT_ENOUGH && kbd_ajusted_at >= ML_BRIGHT_ENOUGH )); then
#    elif (( light < ML_BRIGHT_ENOUGH )); then
#        kbd_to=$ML_KBD_BRIGHT
    else
# Old
#        kbd_to=$kbd_from
     kbd_to=$(echo "$kbd_max - ($coef_kbd * $kbd_max * $light / $ML_BRIGHT_ENOUGH)" | bc)
    kbd_to=$(kbd_range $kbd_to)
    fi
        $ML_DEBUG &&  echo "kbd_from->to: $kbd_from -> $kbd_to"
        if [ "$kbd_from" == "$kbd_to" ]; then
                $ML_DEBUG && echo "kbd threshold not reached($kbd_from->$kbd_to), skip update" && echo
                return
        fi
    $ML_DEBUG && echo light:$light, kbd_ajusted_at:$kbd_ajusted_at, ML_KBD_BRIGHT: $ML_KBD_BRIGHT
    kbd_ajusted_at=$light
    transition $kbd_from $kbd_to $kbd_file
}

function update {
    $ML_DEBUG && echo updating
    lid=$(awk '{print $2}' $lid_file)
    if [ "$lid" == "closed" ]; then
        $ML_DEBUG && echo lid closed, skip update
        return
    fi

    light=$(get_light)
         echo

  if [ $ML_AUTO_SCREEN ] && [ $ML_AUTO_KBD ]; then
                $ML_DEBUG && echo "ML_AUTO_SCREEN and ML_AUTO_KBD are true, running in parallel"
                update_screen $light &
                update_kbd $light &
                wait
  else
    $ML_AUTO_SCREEN && update_screen $light
    $ML_AUTO_KBD && update_kbd $light
        fi
        echo
                $ML_DEBUG && echo -e "light: ${light}           coef: $coef             br_eno: $ML_BRIGHT_ENOUGH\nscreen from/to/max $screen_from/$screen_to/${screen_max}\nkeyboard from/to/max $kbd_from/$kbd_to/$kbd_max"
                echo
}

function watch {
    $ML_DEBUG && echo watching light change...
    while true; do
        update
        sleep $ML_INTERVAL
    done
}

function power_coef {
    power=$(cat $power_file)
    if [ "$power" == 0 ]; then
        echo "1 - $ML_BATTERY_DIM" | bc
    else
        echo 1
    fi
}

function init {
    $ML_DEBUG && echo initializing backlights...

    light=$(get_light)

    screen_ajusted_at=$light
    kbd_ajusted_at=$light
    coef=$(power_coef)
    coef_kbd=$(echo "2 - $coef" | bc)

    if (( light >= ML_BRIGHT_ENOUGH )); then
        screen_to=$screen_max
        kbd_to=0
    else
        screen_to=$(echo "1.4 * $coef * $screen_max * $light / $ML_BRIGHT_ENOUGH" | bc)
        screen_to=$(screen_range $screen_to)
        kbd_to=$(echo "$kbd_max - ($coef_kbd * $kbd_max * $light / $ML_BRIGHT_ENOUGH)" | bc)
        kbd_to=$(kbd_range $kbd_to)
    fi

    screen_from=$(cat $screen_file)
    kbd_from=$(cat $kbd_file)

        if [ $ML_AUTO_SCREEN ] && [ $ML_AUTO_KBD ]; then
                $ML_DEBUG && echo "ML_AUTO_SCREEN and ML_AUTO_KBD are true, running in parallel"
                        transition $screen_from $screen_to $screen_file &
                        transition $kbd_from $kbd_to $kbd_file &
                        wait
        else
                $ML_AUTO_SCREEN && transition $screen_from $screen_to $screen_file
    $ML_AUTO_KBD && transition $kbd_from $kbd_to $kbd_file
        fi
}

init
watch
