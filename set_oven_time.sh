#!/bin/bash

export TZ="Europe/Brussels"
CURRENT_TIME=$(date +"%Y-%m-%dT%H:%M:%S")

JSON_PAYLOAD=$(cat <<EOF
{
    "commands" : [
        {
            "component" : "main",
            "capability" : "execute",
            "command" : "execute",
            "arguments" : [
                "/configuration/vs/0",
                {
                    "x.com.samsung.da.currentTime" : "$CURRENT_TIME"
                }
            ]
        }
    ]
}
EOF
)

echo "Setting oven time to: $CURRENT_TIME (Europe/Brussels)"

curl -X POST "https://api.smartthings.com/v1/devices/$DEVICE_ID/commands" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "$JSON_PAYLOAD"
