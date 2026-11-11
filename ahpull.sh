#!/bin/bash
# Null-safe version: realms/regions that return no auction-house list (e.g. WoW Classic
# "forever" realms without faction-separated auction houses, or regions without forever
# realms) are logged and skipped/fallen back instead of crashing jq with
# "Cannot iterate over null".

mkdir -p data/tmp data/auctions

# Fetch one auctions URL and write it as a CSV. $1=url $2=connectedRealmId $3=ahid label
write_auctions() {
    local url=$1 connectedRealmId=$2 ahid=$3
    local write_date response count file
    write_date=$(date +%s%3N)
    file=$namespace$region$connectedRealmId$write_date.csv
    response=$(curl -s --header "Authorization: Bearer $access_token" "$url")
    count=$(echo "$response" | jq '(.auctions // []) | length' 2>/dev/null)
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        echo "WARN: no auctions at $url -> $(echo "$response" | head -c 200)" >&2
        return 1
    fi
    echo "$response" |
    jq -r --arg region "$namespace$region" --argjson crid "$connectedRealmId" --arg ahid "$ahid" --argjson t "$write_date" '
        .auctions[]? |
        [ $region, $crid, $ahid, .id, $t, .item.id, .item.rand, .item.seed, .time_left, .bid, .buyout, .quantity ] |
        map(. // "" | tostring) | join(";")' > "data/tmp/$file"
    mv "data/tmp/$file" "data/auctions/$file"
}

curl -s -u $client_id:$client_secret -d grant_type=client_credentials https://oauth.battle.net/token | jq -r '.access_token // empty' |
while read access_token;
do
    jq -r '.[].regions[]' namespaces.json |
    while read region;
    do
        jq -r '.[].namespaces[].dynamic' namespaces.json |
        while read namespace;
        do
            curl -s --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/index?namespace=$namespace$region" |
            jq -r '.connected_realms[]?.href' |
            while read connectedRealmId;
            do
                connectedRealmId=${connectedRealmId##*/}
                connectedRealmId=${connectedRealmId%\?*}
                base="https://$region.api.blizzard.com/data/wow/connected-realm/$connectedRealmId/auctions"
                ahids=$(curl -s --header "Authorization: Bearer $access_token" "$base/index?namespace=$namespace$region" |
                        jq -r '.auctions[]?.id' 2>/dev/null)
                if [ -n "$ahids" ]; then
                    # Faction-separated (or any listed) auction houses
                    for ahid in $ahids; do
                        write_auctions "$base/$ahid?namespace=$namespace$region" "$connectedRealmId" "$ahid"
                    done
                else
                    # No AH list: try the single, realm-wide auctions endpoint instead
                    echo "INFO: no auction house list for $namespace$region realm $connectedRealmId, trying $base" >&2
                    write_auctions "$base?namespace=$namespace$region" "$connectedRealmId" "all"
                fi
            done
        done
    done
done
