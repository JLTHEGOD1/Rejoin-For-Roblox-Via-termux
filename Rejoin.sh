#!/data/data/com.termux/files/usr/bin/bash

 echo " _____           _       _       "
 echo "|  __ \         | |     (_)      "
 echp "| |__) |___     | | ___  _ _ __  "
 echo "|  _  // _ \_   | |/ _ \| | '_ \ "
 echo "| | \ \  __/ |__| | (_) | | | | |"
 echo "|_|  \_\___|\____/ \___/|_|_| |_|"
 echo "Made By Larenz v1.0"                                 
                                                                                                  
# Install requirements
pkg update -y
pkg install termux-api curl jq -y

mkdir -p ~/rejoin-tool
CONFIG_JSON=~/rejoin-tool/config.json
LOCK_FILE=~/rejoin-tool/auto_rejoin.lock
WEBHOOK_INTERVAL=300  # seconds for periodic update (default 5 minutes)

# --- FIRST TIME SETUP ---
if [ ! -f "$CONFIG_JSON" ]; then
    echo "=== Initial Setup ==="
    
    read -p "Enter Place ID: " PID
    read -p "Enter Discord Webhook URL: " HOOK
    read -p "Enter Job ID (0 to skip): " JOB
    [ "$JOB" = "0" ] && JOB=""

    # Auto-detect username
    USERNAME=$(strings /data/data/com.roblox.client/shared_prefs/*.xml 2>/dev/null | grep -oP '(?<=\"Username\">)[^<]+' | head -n 1)
    [ -z "$USERNAME" ] && USERNAME="UnknownUser"

    # Save to JSON
    cat <<EOF > $CONFIG_JSON
{
    "username": "$USERNAME",
    "place_id": "$PID",
    "job_id": "$JOB",
    "webhook_url": "$HOOK",
    "package": "com.roblox.client",
    "auto_rejoin_enabled": false
}
EOF

    echo "Setup complete!"
fi

# --- READ JSON VALUES ---
get_json_value() { jq -r ".$1" "$CONFIG_JSON"; }
set_json_value() { tmp=$(mktemp); jq ".$1=\"$2\"" "$CONFIG_JSON" > "$tmp" && mv "$tmp" "$CONFIG_JSON"; }

USERNAME=$(get_json_value "username")
PLACE_ID=$(get_json_value "place_id")
JOB_ID=$(get_json_value "job_id")
WEBHOOK=$(get_json_value "webhook_url")
PACKAGE=$(get_json_value "package")
AUTO_REJOIN=$(get_json_value "auto_rejoin_enabled")

# --- Webhook function ---
send_webhook() {
    local message="$1"
    local screenshot="$2"

    if [ -n "$WEBHOOK" ]; then
        curl -X POST "$WEBHOOK" \
             -F "content=$message" \
             -F "file=@$screenshot"
    fi
}

# --- Periodic dashboard updates ---
periodic_webhook() {
    while [ -f "$LOCK_FILE" ]; do
        SCREENSHOT="$HOME/rejoin-tool/last.png"
        termux-screenshot "$SCREENSHOT"
        MESSAGE="📊 Dashboard Update
Username: $USERNAME
Place ID: $PLACE_ID
Job ID: ${JOB_ID:-None}
Auto Rejoin: $AUTO_REJOIN"
        send_webhook "$MESSAGE" "$SCREENSHOT"
        sleep $WEBHOOK_INTERVAL
    done
}

# --- Get current Roblox Job ID and Place ID if possible ---
get_current_jobid_placeid() {
    # This is a placeholder: Termux cannot directly get Job ID from Roblox process.
    # We'll simulate it: if Roblox is running, assume user is in some Place ID
    # In practice, without Roblox API, we cannot detect exact Job ID
    # For smarter implementation, this requires Roblox API or network sniffing
    CURRENT_JOBID=""   # leave empty if unknown
    CURRENT_PLACEID="" # leave empty if unknown
}

# --- AUTO REJOIN LOOP (SMART) ---
auto_rejoin() {
    touch $LOCK_FILE
    echo "Auto Rejoin Loop Started. Press CTRL+C to stop."
    trap "rm -f $LOCK_FILE; exit" SIGINT SIGTERM

    periodic_webhook &  # start periodic updates in background

    while [ -f "$LOCK_FILE" ]; do
        clear
        echo "====== ROBLOX AUTO REJOIN DASHBOARD ======"
        echo "Username: $USERNAME"
        echo "Place ID: $PLACE_ID"
        echo "Job ID: ${JOB_ID:-None}"
        echo "Auto Rejoin: $AUTO_REJOIN"
        echo "Checking Roblox status..."
        echo "=========================================="

        CHECK=$(pidof $PACKAGE)

        if [ "$AUTO_REJOIN" = "true" ]; then
            get_current_jobid_placeid

            # Decide if we need to reconnect
            REJOIN=false
            if [ -z "$CHECK" ]; then
                # Roblox closed
                REJOIN=true
            elif [ -n "$CURRENT_PLACEID" ] && [ "$CURRENT_PLACEID" != "$PLACE_ID" ]; then
                REJOIN=true
            elif [ -n "$JOB_ID" ] && [ -n "$CURRENT_JOBID" ] && [ "$CURRENT_JOBID" != "$JOB_ID" ]; then
                REJOIN=true
            fi

            if [ "$REJOIN" = true ]; then
                echo "⚠️ Rejoining due to crash, wrong place, or wrong server..."
                SCREENSHOT="$HOME/rejoin-tool/last.png"
                termux-screenshot "$SCREENSHOT"
                send_webhook "⚠️ Auto Rejoin triggered for $USERNAME (Place: $PLACE_ID, Job: ${JOB_ID:-None})" "$SCREENSHOT"

                if [ -z "$JOB_ID" ]; then
                    am start -a android.intent.action.VIEW -d "roblox://placeId=$PLACE_ID"
                else
                    am start -a android.intent.action.VIEW -d "roblox://placeId=$PLACE_ID&gameInstanceId=$JOB_ID"
                fi
                sleep 10
            else
                echo "✅ Roblox is running correctly. No action needed."
            fi
        else
            echo "Auto Rejoin Disabled."
        fi

        sleep 5
    done
}

# --- MENU LOOP ---
while true; do
    clear
    echo "====== ROBLOX REJOIN TOOL (SMART AUTO-RECONNECT) ======"
    echo "Username: $USERNAME"
    echo "PlaceID: $PLACE_ID"
    echo "JobID: ${JOB_ID:-None}"
    echo "Webhook: $WEBHOOK"
    echo "Auto Rejoin: $AUTO_REJOIN"
    echo ""
    echo "1) Rejoin SAME server"
    echo "2) Rejoin NEW server"
    echo "3) Kill Roblox"
    echo "4) Launch Roblox"
    echo "5) Change Place ID"
    echo "6) Change Job ID"
    echo "7) Change Webhook URL"
    echo "8) Start AUTO REJOIN LOOP"
    echo "9) Toggle Auto Rejoin"
    echo "0) Exit"
    read -p "Choose: " opt

    case $opt in
        1)
            am force-stop $PACKAGE
            sleep 1
            am start -a android.intent.action.VIEW -d "roblox://placeId=$PLACE_ID&gameInstanceId=$JOB_ID"
            SCREENSHOT="$HOME/rejoin-tool/last.png"
            termux-screenshot "$SCREENSHOT"
            send_webhook "🔁 Rejoined SAME server: $PLACE_ID, Job: ${JOB_ID:-None}" "$SCREENSHOT"
            ;;
        2)
            am force-stop $PACKAGE
            sleep 1
            am start -a android.intent.action.VIEW -d "roblox://placeId=$PLACE_ID"
            SCREENSHOT="$HOME/rejoin-tool/last.png"
            termux-screenshot "$SCREENSHOT"
            send_webhook "🔁 Rejoined NEW server: $PLACE_ID" "$SCREENSHOT"
            ;;
        3)
            am force-stop $PACKAGE
            ;;
        4)
            am start -n com.roblox.client/com.roblox.client.Activity
            SCREENSHOT="$HOME/rejoin-tool/last.png"
            termux-screenshot "$SCREENSHOT"
            send_webhook "✅ Roblox launched manually by $USERNAME" "$SCREENSHOT"
            ;;
        5)
            read -p "New Place ID: " x
            set_json_value "place_id" "$x"
            PLACE_ID="$x"
            ;;
        6)
            read -p "New Job ID (0 = remove): " x
            [ "$x" = "0" ] && x=""
            set_json_value "job_id" "$x"
            JOB_ID="$x"
            ;;
        7)
            read -p "New Webhook URL: " x
            set_json_value "webhook_url" "$x"
            WEBHOOK="$x"
            ;;
        8)
            auto_rejoin
            ;;
        9)
            if [ "$AUTO_REJOIN" = "true" ]; then
                set_json_value "auto_rejoin_enabled" "false"
                AUTO_REJOIN="false"
                echo "Auto Rejoin DISABLED"
            else
                set_json_value "auto_rejoin_enabled" "true"
                AUTO_REJOIN="true"
                echo "Auto Rejoin ENABLED"
            fi
            sleep 1
            ;;
        0)
            [ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
            exit
            ;;
        *)
            echo "Invalid" && sleep 1
            ;;
    esac
done
