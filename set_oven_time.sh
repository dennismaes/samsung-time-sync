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

echo "Sending request to SmartThings API..."
echo DEVICE_ID: $DEVICE_ID
echo TOKEN: $TOKEN
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://api.smartthings.com/v1/devices/$DEVICE_ID/commands" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "$JSON_PAYLOAD")

HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$ d')

echo "Response status code: $HTTP_STATUS"

if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
    echo "SUCCESS: Time successfully updated on oven"
    echo "Response body:"
    echo "$BODY"
else
    echo "ERROR: Failed to update oven time"
    echo "Status code: $HTTP_STATUS"
    echo "Response body:"
    echo "$BODY"
    exit 1
fi
