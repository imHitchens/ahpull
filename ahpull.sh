#!/bin/bash
# Null-safe version: realms/regions that return no auction-house list (e.g. WoW Classic
# "forever" realms without faction-separated auction houses, or regions without forever
# realms) are logged and skipped/fallen back instead of crashing jq with
# "Cannot iterate over null".

mkdir -p data/tmp data/auctions

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

# Classic auction house IDs -> faction name
ah_name() {
    case "$1" in
        2) echo "Alliance" ;; 6) echo "Horde" ;; 7) echo "Neutral" ;;
        all) echo "realm-wide" ;; *) echo "unknown" ;;
    esac
}

# Fetch one auctions URL and write it as a CSV. $1=url $2=connectedRealmId $3=ahid label
write_auctions() {
    local url=$1 connectedRealmId=$2 ahid=$3
    local write_date response count file
    write_date=$(date +%s%3N)
    file=$namespace$region$connectedRealmId$write_date.csv
    log "FETCH $namespace$region realm $connectedRealmId AH $ahid ($(ah_name $ahid))"
    response=$(curl -s --header "Authorization: Bearer $access_token" "$url")
    count=$(echo "$response" | jq '(.auctions // []) | length' 2>/dev/null)
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        log "WARN  $namespace$region realm $connectedRealmId AH $ahid ($(ah_name $ahid)): no auctions -> $(echo "$response" | head -c 200)"
        return 1
    fi
    echo "$response" |
    jq -r --arg region "$namespace$region" --argjson crid "$connectedRealmId" --arg ahid "$ahid" --argjson t "$write_date" '
        .auctions[]? |
        [ $region, $crid, $ahid, .id, $t, .item.id, .item.rand, .item.seed, .time_left, .bid, .buyout, .quantity ] |
        map(. // "" | tostring) | join(";")' > "data/tmp/$file"
    mv "data/tmp/$file" "data/auctions/$file"
    log "OK    $namespace$region realm $connectedRealmId AH $ahid ($(ah_name $ahid)): $count auctions -> data/auctions/$file"
}

log "Starting run"
curl -s -u $client_id:$client_secret -d grant_type=client_credentials https://oauth.battle.net/token | jq -r '.access_token // empty' |
while read access_token;
do
    jq -r '.[].regions[]' namespaces.json |
    while read region;
    do
        jq -r '.[].namespaces | to_entries[] | "\(.key) \(.value.dynamic)"' namespaces.json |
        while read label namespace;
        do
            if [ "$label" = "forever" ]; then
                # Forever has no realms: auction houses hang off rulesets instead
                # (/data/wow/ruleset/{id}/auctions/ — trailing slash required).
                log "RULESETS $namespace$region: fetching ruleset index"
                rulesets=$(curl -s --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/ruleset/index?namespace=$namespace$region")
                rsids=$(echo "$rulesets" | jq -r '.rulesets[]?.id' 2>/dev/null)
                if [ -z "$rsids" ]; then
                    log "WARN  $namespace$region: no rulesets -> $(echo "$rulesets" | head -c 200)"
                    continue
                fi
                log "RULESETS $namespace$region: $(echo "$rsids" | wc -l) rulesets"
                for rsid in $rsids; do
                    base="https://$region.api.blizzard.com/data/wow/ruleset/$rsid/auctions"
                    ahids=$(curl -s --header "Authorization: Bearer $access_token" "$base/?namespace=$namespace$region" | jq -r '.auctions[]?.id' 2>/dev/null)
                    if [ -z "$ahids" ]; then
                        log "WARN  $namespace$region ruleset $rsid: no auction houses"
                        continue
                    fi
                    log "RULESET $namespace$region ruleset $rsid: auction houses $(echo $ahids)"
                    for ahid in $ahids; do
                        write_auctions "$base/$ahid?namespace=$namespace$region" "$rsid" "$ahid"
                    done
                done
                continue
            fi

            log "REALMS $namespace$region: fetching connected realm index"
            realms=$(curl -s --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/index?namespace=$namespace$region")
            hrefs=$(echo "$realms" | jq -r '.connected_realms[]?.href' 2>/dev/null)
            if [ -z "$hrefs" ]; then
                log "WARN  $namespace$region: no connected realms -> $(echo "$realms" | head -c 200)"
                continue
            fi
            log "REALMS $namespace$region: $(echo "$hrefs" | wc -l) connected realms"
            echo "$hrefs" |
            while read connectedRealmId;
            do
                connectedRealmId=${connectedRealmId##*/}
                connectedRealmId=${connectedRealmId%\?*}
                log "REALM $namespace$region realm $connectedRealmId: fetching auction house index"
                base="https://$region.api.blizzard.com/data/wow/connected-realm/$connectedRealmId/auctions"
                ahids=$(curl -s --header "Authorization: Bearer $access_token" "$base/index?namespace=$namespace$region" |
                        jq -r '.auctions[]?.id' 2>/dev/null)
                if [ -n "$ahids" ]; then
                    log "REALM $namespace$region realm $connectedRealmId: auction houses $(echo $ahids)"
                    # Faction-separated (or any listed) auction houses
                    for ahid in $ahids; do
                        write_auctions "$base/$ahid?namespace=$namespace$region" "$connectedRealmId" "$ahid"
                    done
                else
                    # No AH list: try the single, realm-wide auctions endpoint instead
                    log "INFO  $namespace$region realm $connectedRealmId: no auction house list, trying realm-wide endpoint"
                    write_auctions "$base?namespace=$namespace$region" "$connectedRealmId" "all"
                fi
            done
        done
    done
done
log "Run finished"
