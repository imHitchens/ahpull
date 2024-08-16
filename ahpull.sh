#!bin/bash
curl -u $client_id:$client_secret -d grant_type=client_credentials https://oauth.battle.net/token | jq -r '.access_token' | 
while read access_token;
do 
    cat namespaces.json | jq -r '.[].regions.[]' |
    while read region;
    do 
        cat namespaces.json | jq -r '.[].namespaces.[].dynamic' |
        while read namespace;
        do
            curl --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/index?namespace=$namespace$region" |
            jq -r '.connected_realms[].href' |
            while read connectedRealmId;
            do
                connectedRealmId=${connectedRealmId##*/}
                connectedRealmId=${connectedRealmId%\?*}
                curl --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/$connectedRealmId/auctions/index?namespace=$namespace$region&locale=$locale&access_token=$access_token" | jq '.auctions[]' | jq '.id' | 
                while read ahid;
                do
                    mkdir -p data/$namespace$region/$connectedRealmId/$ahid
                    curl --header "Authorization: Bearer $access_token" "https://$region.api.blizzard.com/data/wow/connected-realm/$connectedRealmId/auctions/$ahid?namespace=$namespace$region&$locale&$access_token" -o data/$namespace$region/$connectedRealmId/$ahid/$(date +%s).json;
                done;
            done;
        done;
    done;
done