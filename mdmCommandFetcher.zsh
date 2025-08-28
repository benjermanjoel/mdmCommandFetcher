#!/bin/zsh --no-rcs

####################################################################################################
# This script's purpose is to run a GET against a Jamf Pro server's '/v2/mdm/commands' endpoint to retrieve MDM command data using a client credential.
# Needed permissons for API Role: "View MDM command information in Jamf Pro API"
####################################################################################################
# Changelog:
# Created 08/28/2025 - Benjamin Julian
####################################################################################################

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#        * Redistributions of source code must retain the above copyright
#         notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#           notice, this list of conditions and the following disclaimer in the
#           documentation and/or other materials provided with the distribution.
#         * Neither the name of the JAMF Software, LLC nor the
#           names of its contributors may be used to endorse or promote products
#           derived from this software without specific prior written permission.
# THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
# EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
####################################################################################################

# ========================
# Jamf Pro API connection
# ========================
url="https://yourserver.jamfcloud.com"   # <-- replace with your Jamf Cloud URL
client_id="your-client-id"               # <-- replace with your client_id
client_secret="yourClientSecret"         # <-- replace with your client_secret

access_token=""
token_expiration_epoch=0

getAccessToken() {
  response=$(curl --silent --location --request POST "${url}/api/oauth/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${client_id}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=${client_secret}")
  access_token=$(echo "$response" | plutil -extract access_token raw -)
  token_expires_in=$(echo "$response" | plutil -extract expires_in raw -)
  token_expiration_epoch=$(($current_epoch + $token_expires_in - 1))
}

checkTokenExpiration() {
  current_epoch=$(date +%s)
    if [[ token_expiration_epoch -ge current_epoch ]]
    then
        echo "Token valid until the following epoch time: " "$token_expiration_epoch"
    else
        echo "No valid token available, getting new token"
        getAccessToken
    fi
}

invalidateToken() {
  responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${access_token}" $url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
  if [[ ${responseCode} == 204 ]]
  then
    echo "Token successfully invalidated"
    access_token=""
    token_expiration_epoch="0"
  elif [[ ${responseCode} == 401 ]]
  then
    echo "Token already invalid"
  else
    echo "An unknown error occurred invalidating the token"
  fi
}

# ========================
# Prompt for filter values via a single GUI dialog sequence
# ========================
read -r commandStatus clientType pageSize <<<$(osascript <<EOT
tell application "System Events"
  set stat to text returned of (display dialog "Enter status:" default answer "eg. Pending, Acknowledged" buttons {"OK"} default button "OK")
  set ctype to text returned of (display dialog "Enter clientType:" default answer "eg. COMPUTER, MOBILE_DEVICE" buttons {"OK"} default button "OK")
  set psize to text returned of (display dialog "Enter page size (default 100):" default answer "100" buttons {"OK"} default button "OK")
  return stat & " " & ctype & " " & psize
end tell
EOT
)

if [[ -z "$pageSize" ]]; then
  pageSize=100
fi

# ========================
# Build query
# ========================

FILTER="status==${commandStatus};clientType==${clientType}"
OUTPUT_FILE="$HOME/Desktop/mdm_commands_results.txt"
ENDPOINT="${url}/api/v2/mdm/commands"

# Clear any old file
: > "$OUTPUT_FILE"

# ========================
# Page through results
# ========================
page=0
while true; do
  checkTokenExpiration
  response=$(curl -v -X GET "${ENDPOINT}?page=${page}&page-size=${pageSize}&sort=dateSent%3Aasc&filter=${FILTER}" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Accept: application/json")

  # Extract results array length
  result_count=$(echo "$response" | jq '.results | length')

  if [[ "$result_count" -eq 0 ]]; then
    break
  fi

  echo "$response" | jq '.' >> "$OUTPUT_FILE"
  page=$((page+1))
done

echo "All pages retrieved. Results saved to: ${OUTPUT_FILE}"

# Optional: Invalidate token when done
# invalidateToken